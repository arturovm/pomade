//// Mustache syntactical grammar:
////
//// template        -> {expression} EOF ;
//// expression      -> LineStart ;
//// LineStart       -> LINE_START | Indent ;
//// Indent          -> INDENT | Leading ;
//// Leading         -> LEADING | Parameter ;
//// Parameter       -> BLOCK_START {expression} END | Parent ;
//// Parent          -> PARENT_START {Argument / expression => empty} END | InvertedSection ;
//// Argument        -> BLOCK_START {expression} END;
//// InvertedSection -> INVERTED_SECTION_START {expression} END | Section;
//// Section         -> SECTION_START {expression} END | Partial ;
//// Partial         -> PARTIAL | RawVariable ;
//// RawVariable     -> (TRIPLE_MUSTACHE | RAW_VARIABLE) | Variable ;
//// Variable        -> VARIABLE | Literal ;
//// Literal         -> TEXT | WHITESPACE | NEWLINE ;

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import pomade/internal/rewriter
import pomade/internal/scanner

pub type Expression {
  // LineStart is a special expression used as a marker for applying indentation
  // at runtime, and to manipulate whitespace at the beginning of a line. I
  // added this expression solely to deal with the rules of the inheritance spec
  // around indentation and de-indentation
  LineStart(Option(String))
  Literal(value: String)
  Variable(path: List(String))
  RawVariable(path: List(String))
  Section(path: List(String), content: List(Expression))
  InvertedSection(path: List(String), content: List(Expression))
  Partial(name: scanner.PartialName, indentation: Option(String))
  InlinePartial(name: scanner.PartialName)
  Parameter(
    name: String,
    indentation: Option(String),
    content: List(Expression),
  )
  InlineParameter(name: String, content: List(Expression))
  Parent(name: String, indentation: Option(String), arguments: List(Argument))
  InlineParent(name: String, arguments: List(Argument))
}

pub type Argument {
  Argument(name: String, content: List(Expression))
}

/// `SyntaxError` represents an error encountered during parsing.
pub type SyntaxError {
  /// `UnexpectedTokenError` is returned when a token different from what the
  /// grammar indicates is found.
  UnexpectedTokenError(rewriter.Element)
  /// `UnexpectedEndOfInputError` is used to report that more tokens were
  /// expected, but the parser unexpectedly consumed the whole input.
  UnexpectedEndOfInputError
  /// `NoMatchingClosingTagError` is returned when a `{{/closing_tag}}` was
  /// expected, but none was found.
  NoMatchingEndTagError(rewriter.Element)
}

pub fn parse(
  tokens: List(rewriter.Element),
) -> Result(List(Expression), SyntaxError) {
  parse_template(tokens)
}

// rules

fn parse_template(
  tokens: List(rewriter.Element),
) -> Result(List(Expression), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, []))
  case tail {
    [rewriter.Eof(_)] -> Ok(expressions)
    [token, ..] -> Error(UnexpectedTokenError(token))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_expressions(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case parse_expressions_reversed(tokens, acc) {
    Ok(#(acc, tail)) -> Ok(#(list.reverse(acc), tail))
    error -> error
  }
}

fn parse_expressions_reversed(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_)] | [rewriter.End(_, _, _), ..] -> Ok(#(acc, tokens))
    non_empty ->
      case parse_expression(non_empty, acc) {
        Ok(#(acc, tail)) -> parse_expressions_reversed(tail, acc)
        Error(error) -> Error(error)
      }
  }
}

fn parse_expression(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  parse_line_start(tokens, acc)
}

fn parse_line_start(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.LineStart(_, leading), ..tail] ->
      Ok(#([LineStart(leading), ..acc], tail))
    _ -> parse_parameter(tokens, acc)
  }
}

fn parse_parameter(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.BlockStart(_, name, start_clearance) as tag, ..block_tail] -> {
      use #(reversed_expressions, tail) <- result.try(
        parse_expressions_reversed(block_tail, []),
      )
      use #(end_clearance, tail) <- result.map(
        parse_end_tag(tail, [name])
        |> result.map_error(fn(_) { NoMatchingEndTagError(tag) }),
      )
      let acc =
        build_parameter(
          name,
          start_clearance,
          reversed_expressions,
          end_clearance,
          block_tail,
          acc,
        )
      #(acc, tail)
    }
    _ -> parse_parent(tokens, acc)
  }
}

fn build_parameter(
  name: String,
  start_clearance: rewriter.Clearance,
  reversed_expressions: List(Expression),
  end_clearance: rewriter.Clearance,
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> List(Expression) {
  case standalone(start_clearance, end_clearance) {
    True ->
      build_standalone_parameter(
        name,
        start_clearance,
        reversed_expressions,
        end_clearance,
        tokens,
        acc,
      )

    False ->
      build_inline_parameter(
        name,
        start_clearance,
        reversed_expressions,
        end_clearance,
        acc,
      )
  }
}

fn build_standalone_parameter(
  name: String,
  start_clearance: rewriter.Clearance,
  reversed_expressions: List(Expression),
  end_clearance: rewriter.Clearance,
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> List(Expression) {
  let intrinsic_indentation = intrinsic_indentation(start_clearance, tokens)
  let extrinsic_indentation = extrinsic_parameter_indentation(start_clearance)
  let expressions =
    list.reverse(reversed_expressions)
    |> deindent(intrinsic_indentation)
  list.prepend(
    acc,
    Parameter(
      name,
      option.or(intrinsic_indentation, extrinsic_indentation),
      expressions,
    ),
  )
  |> insert_end_trailing(end_clearance)
}

fn build_inline_parameter(
  name: String,
  start_clearance: rewriter.Clearance,
  reversed_expressions: List(Expression),
  end_clearance: rewriter.Clearance,
  acc: List(Expression),
) -> List(Expression) {
  let expressions =
    insert_end_leading(reversed_expressions, end_clearance)
    |> list.reverse()
    |> insert_start_trailing(start_clearance)
  insert_start_leading(acc, start_clearance)
  |> list.prepend(InlineParameter(name, expressions))
  |> insert_end_trailing(end_clearance)
}

fn parse_parent(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.ParentStart(_, name, start_clearance) as tag, ..tail] -> {
      use #(expressions, tail) <- result.try(parse_arguments(tail, []))
      use #(end_clearance, tail) <- result.map(
        parse_end_tag(tail, [name])
        |> result.map_error(fn(_) { NoMatchingEndTagError(tag) }),
      )
      let acc = case standalone(start_clearance, end_clearance) {
        True -> {
          let indentation = extrinsic_indentation(start_clearance)
          [Parent(name, indentation, expressions), ..acc]
        }
        False ->
          insert_parent_start_leading(acc, start_clearance)
          |> list.prepend(InlineParent(name, expressions))
          |> insert_parent_end_trailing(end_clearance)
      }
      #(acc, tail)
    }
    _ -> parse_inverted_section(tokens, acc)
  }
}

fn parse_arguments(
  tokens: List(rewriter.Element),
  acc: List(Argument),
) -> Result(#(List(Argument), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_)] | [rewriter.End(_, _, _), ..] ->
      Ok(#(list.reverse(acc), tokens))
    [rewriter.BlockStart(_, name, start_clearance) as tag, ..tail] ->
      case parse_argument(tail, tag, name, start_clearance) {
        Ok(#(argument, tail)) -> parse_arguments(tail, [argument, ..acc])
        Error(error) -> Error(error)
      }
    other ->
      case parse_expression(other, []) {
        Ok(#(_, tail)) -> parse_arguments(tail, acc)
        Error(error) -> Error(error)
      }
  }
}

fn parse_argument(
  tokens: List(rewriter.Element),
  start: rewriter.Element,
  name: String,
  start_clearance: rewriter.Clearance,
) -> Result(#(Argument, List(rewriter.Element)), SyntaxError) {
  use #(reversed_expressions, tail) <- result.try(
    parse_expressions_reversed(tokens, []),
  )
  use #(_, tail) <- result.map(
    parse_end_tag(tail, [name])
    |> result.map_error(fn(_) { NoMatchingEndTagError(start) }),
  )
  let intrinsic_indentation = intrinsic_indentation(start_clearance, tokens)
  let expressions =
    list.reverse(reversed_expressions)
    |> deindent(intrinsic_indentation)
  #(Argument(name, expressions), tail)
}

fn parse_inverted_section(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, start_path) as start, ..tail] -> {
      use #(reversed_expressions, tail) <- result.try(
        parse_expressions_reversed(tail, []),
      )
      use #(end_clearance, tail) <- result.map(
        parse_end_tag(tail, start_path)
        |> result.map_error(fn(_) { NoMatchingEndTagError(start) }),
      )
      let expressions =
        insert_end_leading(reversed_expressions, end_clearance)
        |> list.reverse()
      let acc =
        list.prepend(acc, InvertedSection(start_path, expressions))
        |> insert_end_trailing(end_clearance)
      #(acc, tail)
    }
    _ -> parse_section(tokens, acc)
  }
}

fn parse_section(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, start_path) as start, ..tail] -> {
      use #(reversed_expressions, tail) <- result.try(
        parse_expressions_reversed(tail, []),
      )
      use #(end_clearance, tail) <- result.map(
        parse_end_tag(tail, start_path)
        |> result.map_error(fn(_) { NoMatchingEndTagError(start) }),
      )
      let expressions =
        insert_end_leading(reversed_expressions, end_clearance)
        |> list.reverse()
      let acc =
        list.prepend(acc, Section(start_path, expressions))
        |> insert_end_trailing(end_clearance)
      #(acc, tail)
    }
    _ -> parse_partial(tokens, acc)
  }
}

fn parse_end_tag(
  tokens: List(rewriter.Element),
  name: List(String),
) -> Result(#(rewriter.Clearance, List(rewriter.Element)), Nil) {
  case tokens {
    [rewriter.End(_, end_name, clearance), ..tail] if end_name == name ->
      Ok(#(clearance, tail))
    _ -> Error(Nil)
  }
}

fn parse_partial(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Partial(_, name, indentation), ..tail] ->
      Ok(#([Partial(name, indentation), ..acc], tail))
    _ -> parse_inline_partial(tokens, acc)
  }
}

fn parse_inline_partial(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.InlinePartial(_, name), ..tail] ->
      Ok(#([InlinePartial(name), ..acc], tail))
    _ -> parse_raw_variable(tokens, acc)
  }
}

fn parse_raw_variable(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.RawVariable(_, path), ..tail] ->
      Ok(#([RawVariable(path), ..acc], tail))
    _ -> parse_variable(tokens, acc)
  }
}

fn parse_variable(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Variable(_, path), ..tail] -> Ok(#([Variable(path), ..acc], tail))
    _ -> parse_primary(tokens, acc)
  }
}

fn parse_primary(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Literal(_, value), ..tail] -> Ok(#([Literal(value), ..acc], tail))
    [any, ..] -> Error(UnexpectedTokenError(any))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// helpers

fn standalone(start: rewriter.Clearance, end: rewriter.Clearance) -> Bool {
  case start, end {
    rewriter.Clearance(rewriter.Clears(_), _),
      rewriter.Clearance(_, rewriter.Clears(_))
    -> True
    _, _ -> False
  }
}

fn intrinsic_indentation(
  start: rewriter.Clearance,
  tokens: List(rewriter.Element),
) -> Option(String) {
  case start {
    rewriter.Clearance(_, rewriter.Clears(_)) ->
      case tokens {
        [rewriter.LineStart(_, Some(lexeme)), ..]
        | [
            rewriter.BlockStart(
              _,
              _,
              rewriter.Clearance(
                rewriter.Clears(Some(lexeme)),
                rewriter.NotClears,
              ),
            ),
          ]
        | [
            rewriter.ParentStart(
              _,
              _,
              rewriter.Clearance(
                rewriter.Clears(Some(lexeme)),
                rewriter.NotClears,
              ),
            ),
          ]
        | [
            rewriter.End(
              _,
              _,
              rewriter.Clearance(rewriter.Clears(Some(lexeme)), _),
            ),
            ..
          ] -> Some(lexeme)
        _ -> None
      }
    __ -> None
  }
}

fn extrinsic_indentation(start) {
  case start {
    rewriter.Clearance(rewriter.Clears(leading), _) -> leading
    _ -> None
  }
}

fn extrinsic_parameter_indentation(start) {
  case start {
    rewriter.Clearance(rewriter.Clears(leading), rewriter.NotClears) -> leading
    _ -> None
  }
}

fn deindent(
  expressions: List(Expression),
  intrinsic_indentation: Option(String),
) -> List(Expression) {
  case intrinsic_indentation {
    None -> expressions
    Some(intrinsic_indentation) ->
      deindent_loop(expressions, intrinsic_indentation, [])
  }
}

fn deindent_loop(
  expressions: List(Expression),
  by: String,
  acc: List(Expression),
) -> List(Expression) {
  case expressions {
    [] -> list.reverse(acc)
    [LineStart(Some(indentation)), ..tail] ->
      case string.drop_start(indentation, string.length(by)) {
        "" -> deindent_loop(tail, by, [LineStart(None), ..acc])
        indentation ->
          deindent_loop(tail, by, [LineStart(Some(indentation)), ..acc])
      }
    [Section(path, content), ..tail] ->
      deindent_loop(tail, by, [
        Section(path, deindent_loop(content, by, [])),
        ..acc
      ])
    [InvertedSection(path, content), ..tail] ->
      deindent_loop(tail, by, [
        InvertedSection(path, deindent_loop(content, by, [])),
        ..acc
      ])
    [Partial(name, indentation), ..tail] ->
      deindent_loop(tail, by, [
        Partial(
          name,
          option.map(indentation, string.drop_start(_, string.length(by))),
        ),
        ..acc
      ])
    [Parameter(name, indentation, content), ..tail] ->
      deindent_loop(tail, by, [
        Parameter(
          name,
          option.map(indentation, string.drop_start(_, string.length(by))),
          deindent_loop(content, by, []),
        ),
        ..acc
      ])
    [Parent(name, indentation, content), ..tail] ->
      deindent_loop(tail, by, [
        Parent(
          name,
          option.map(indentation, string.drop_start(_, string.length(by))),
          deindent_arguments(content, by, []),
        ),
        ..acc
      ])
    [expression, ..tail] -> deindent_loop(tail, by, [expression, ..acc])
  }
}

fn deindent_arguments(
  arguments: List(Argument),
  by: String,
  acc: List(Argument),
) -> List(Argument) {
  case arguments {
    [] -> list.reverse(acc)
    [Argument(name, content), ..tail] ->
      deindent_arguments(tail, by, [
        Argument(name, deindent_loop(content, by, [])),
        ..acc
      ])
  }
}

fn insert_start_leading(acc: List(Expression), start: rewriter.Clearance) {
  case start {
    rewriter.Clearance(rewriter.Clears(leading), rewriter.NotClears) -> [
      LineStart(leading),
      ..acc
    ]
    _ -> acc
  }
}

fn insert_start_trailing(
  acc: List(Expression),
  start: rewriter.Clearance,
) -> List(Expression) {
  case start {
    rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some(trailing))) -> [
      Literal(trailing),
      ..acc
    ]
    _ -> acc
  }
}

fn insert_end_leading(
  acc: List(Expression),
  end: rewriter.Clearance,
) -> List(Expression) {
  case end {
    rewriter.Clearance(rewriter.Clears(Some(leading)), rewriter.NotClears) -> [
      LineStart(Some(leading)),
      ..acc
    ]
    _ -> acc
  }
}

fn insert_end_trailing(
  acc: List(Expression),
  end: rewriter.Clearance,
) -> List(Expression) {
  case end {
    // if the end tag is not standalone, output whatever trailing whitespace
    // there is
    rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some(trailing))) -> [
      Literal(trailing),
      ..acc
    ]
    // otherwise, elide
    _ -> acc
  }
}

fn insert_parent_start_leading(
  acc: List(Expression),
  start: rewriter.Clearance,
) -> List(Expression) {
  case start {
    rewriter.Clearance(rewriter.Clears(leading), _) -> [
      LineStart(leading),
      ..acc
    ]
    _ -> acc
  }
}

fn insert_parent_end_trailing(
  acc: List(Expression),
  end: rewriter.Clearance,
) -> List(Expression) {
  case end {
    // output whatever trailing whitespace there is
    rewriter.Clearance(_, rewriter.Clears(Some(trailing))) -> [
      Literal(trailing),
      ..acc
    ]
    _ -> acc
  }
}

// formatting

pub fn error_to_string(error: SyntaxError) -> String {
  case error {
    UnexpectedTokenError(token) ->
      "line "
      <> int.to_string(token.line)
      <> ": unexpected token: "
      <> rewriter.token_to_string(token)
    UnexpectedEndOfInputError -> "unexpected end of input"
    NoMatchingEndTagError(token) ->
      "line "
      <> int.to_string(token.line)
      <> ": no matching end tag found for start tag: "
      <> rewriter.token_to_string(token)
  }
}
