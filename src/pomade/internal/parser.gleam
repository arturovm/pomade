//// Mustache syntactical grammar:
////
//// template        -> {expression} EOF ;
//// expression      -> Indent ;
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
  // Indent is a marker for applying indentation at runtime
  Indent
  // Leading is a special expression used to manipulate whitespace at the
  // beginning of a line. I added this expression solely to deal with
  // the weird rules of the inheritance spec around indentation and
  // de-indentation
  Leading(String)
  Literal(value: String)
  Variable(path: List(String))
  RawVariable(path: List(String))
  Section(path: List(String), content: List(Expression))
  InvertedSection(path: List(String), content: List(Expression))
  Partial(name: scanner.PartialName, indentation: Option(String))
  // block parameter
  InlineParameter(name: String, content: List(Expression))
  StandaloneParameter(
    name: String,
    indentation: Option(String),
    content: List(Expression),
  )
  InlineParent(name: String, arguments: List(Argument))
  StandaloneParent(
    name: String,
    indentation: Option(String),
    arguments: List(Argument),
  )
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
  parse_indent(tokens, acc)
}

fn parse_indent(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Indent(_), ..tail] -> Ok(#([Indent, ..acc], tail))
    _ -> parse_leading(tokens, acc)
  }
}

fn parse_leading(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Leading(_, lexeme), ..tail] ->
      Ok(#([Leading(lexeme), ..acc], tail))
    _ -> parse_parameter(tokens, acc)
  }
}

fn parse_parameter(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.BlockStart(_, data) as tag, ..block_content] -> {
      use #(reversed_expressions, tail) <- result.try(
        parse_expressions_reversed(block_content, []),
      )
      let reversed_expressions = remove_indent(reversed_expressions)
      use #(end, tail) <- result.map(parse_end_tag(tail, tag, [data.name]))
      case standalone(data.clearance, end) {
        True -> {
          let expressions = list.reverse(reversed_expressions)
          let expressions = ensure_indent(expressions)
          let intrinsic_indentation = case standalone(data.clearance, end) {
            True -> intrinsic_indentation(data.clearance, block_content)
            False -> None
          }
          let deindented_expressions =
            deindent(intrinsic_indentation, expressions)
          let extrinsic_indentation = extrinsic_indentation(data.clearance, end)
          let acc = insert_standalone_leading(acc, data.clearance, end)
          let acc = [
            StandaloneParameter(
              data.name,
              option.or(intrinsic_indentation, extrinsic_indentation),
              deindented_expressions,
            ),
            ..acc
          ]
          let acc = insert_parameter_trailing(acc, data.clearance, end)
          #(acc, tail)
        }
        False -> {
          let expressions = list.reverse(reversed_expressions)
          let expressions = ensure_indent(expressions)
          let acc = insert_standalone_leading(acc, data.clearance, end)
          let acc = [InlineParameter(data.name, expressions), ..acc]
          let acc = insert_parameter_trailing(acc, data.clearance, end)
          #(acc, tail)
        }
      }
    }
    _ -> parse_parent(tokens, acc)
  }
}

// fn parse_block(
//   tag: rewriter.Element,
//   data: rewriter.StartTagData,
//   tokens: List(rewriter.Element),
// ) -> Result(List(Expression), SyntaxError) {
//   use #(reversed_expressions, tail) <- result.try(
//     parse_expressions_reversed(tokens, []),
//   )
//   let reversed_expressions = remove_indent(reversed_expressions)
//   use #(end, tail) <- result.map(parse_end_tag(tail, tag, [data.name]))
//   list.reverse(reversed_expressions)
// }

fn insert_standalone_leading(
  acc: List(Expression),
  start: rewriter.Clearance,
  end: rewriter.Clearance,
) -> List(Expression) {
  let leading = case start, end {
    // if the pair is standalone, elide
    rewriter.Clearance(rewriter.Clears(_), _),
      rewriter.Clearance(_, rewriter.Clears(_))
    -> None
    // otherwise always output whatever leading whitespace there is
    rewriter.Clearance(rewriter.NotClears, _), _ -> None
    rewriter.Clearance(rewriter.Clears(outer), _), _ -> outer
  }
  case leading {
    None -> acc
    Some(ws) -> [Leading(ws), ..acc]
  }
}

fn insert_parameter_trailing(
  acc: List(Expression),
  start: rewriter.Clearance,
  end: rewriter.Clearance,
) -> List(Expression) {
  let trailing = case start, end {
    // if the pair is standalone, and the end tag itself is standalone, elide
    rewriter.Clearance(rewriter.Clears(_), _),
      rewriter.Clearance(rewriter.Clears(_), rewriter.Clears(_))
    -> None
    // otherwise always output whatever trailing whitespace there is
    _, rewriter.Clearance(_, rewriter.NotClears) -> None
    _, rewriter.Clearance(_, rewriter.Clears(outer)) -> outer
  }
  case trailing {
    None -> acc
    Some(ws) -> [Literal(ws), ..acc]
  }
}

fn parse_parent(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.ParentStart(_, data) as tag, ..tail] -> {
      use #(expressions, tail) <- result.try(parse_arguments(tail, []))
      use #(end, tail) <- result.map(parse_end_tag(tail, tag, [data.name]))
      case standalone(data.clearance, end) {
        True -> {
          let extrinsic_indentation = extrinsic_indentation(data.clearance, end)
          let acc = insert_standalone_leading(acc, data.clearance, end)
          let acc = [
            StandaloneParent(data.name, extrinsic_indentation, expressions),
            ..acc
          ]
          let acc = insert_standalone_trailing(acc, data.clearance, end)
          #(acc, tail)
        }
        False -> {
          let acc = insert_standalone_leading(acc, data.clearance, end)
          let acc = [InlineParent(data.name, expressions), ..acc]
          let acc = insert_standalone_trailing(acc, data.clearance, end)
          #(acc, tail)
        }
      }
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
    [rewriter.BlockStart(_, data) as tag, ..tail] ->
      case parse_argument(tail, tag, data) {
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
  data: rewriter.StartTagData,
) -> Result(#(Argument, List(rewriter.Element)), SyntaxError) {
  use #(reversed_expressions, tail) <- result.try(
    parse_expressions_reversed(tokens, []),
  )
  let reversed_expressions = remove_indent(reversed_expressions)
  let expressions = list.reverse(reversed_expressions)
  use #(_, tail) <- result.map(parse_end_tag(tail, start, [data.name]))
  let expressions = ensure_indent(expressions)
  let intrinsic_indentation = intrinsic_indentation(data.clearance, tokens)
  let deindented_expressions = deindent(intrinsic_indentation, expressions)
  #(Argument(data.name, deindented_expressions), tail)
}

fn insert_standalone_trailing(
  acc: List(Expression),
  start: rewriter.Clearance,
  end: rewriter.Clearance,
) -> List(Expression) {
  let trailing = case start, end {
    // if the pair is standalone, elide
    rewriter.Clearance(rewriter.Clears(_), _),
      rewriter.Clearance(_, rewriter.Clears(_))
    -> None
    // otherwise always output whatever trailing whitespace there is
    _, rewriter.Clearance(_, rewriter.NotClears) -> None
    _, rewriter.Clearance(_, rewriter.Clears(outer)) -> outer
  }
  case trailing {
    None -> acc
    Some(ws) -> [Literal(ws), ..acc]
  }
}

fn parse_inverted_section(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_inverted_section_start, InvertedSection, acc)
    _ -> parse_section(tokens, acc)
  }
}

fn parse_inverted_section_start(
  tokens: List(rewriter.Element),
) -> Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _) as tag, ..tail] -> Ok(#(tag, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_section(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_section_start, Section, acc)
    _ -> parse_partial(tokens, acc)
  }
}

fn parse_section_start(
  tokens: List(rewriter.Element),
) -> Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _) as tag, ..tail] -> Ok(#(tag, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_end_tag(
  tokens: List(rewriter.Element),
  start: rewriter.Element,
  name: List(String),
) -> Result(#(rewriter.Clearance, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.End(_, end_name, clearance), ..tail] if end_name == name ->
      Ok(#(clearance, tail))
    [rewriter.End(_, _, _), ..] -> Error(NoMatchingEndTagError(start))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_partial(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Partial(_, name, indentation), ..tail] ->
      Ok(#([Partial(name, indentation), ..acc], tail))
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

fn parse_enclosed(
  tokens: List(rewriter.Element),
  opening_rule: fn(List(rewriter.Element)) ->
    Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError),
  expr_constructor: fn(List(String), List(Expression)) -> Expression,
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  use #(start, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, []))
  use start_path <- result.try(tag_path(start))
  use #(end, tail) <- result.map(parse_end_tag(tail, start, start_path))
  let acc = [expr_constructor(start_path, expressions), ..acc]
  let acc = insert_end_tag_clearance(acc, end)
  #(acc, tail)
}

fn tag_path(tag: rewriter.Element) -> Result(List(String), SyntaxError) {
  case tag {
    rewriter.SectionStart(_, path) -> Ok(path)
    rewriter.InvertedSectionStart(_, path) -> Ok(path)
    rewriter.End(_, path, _) -> Ok(path)
    rewriter.BlockStart(_, rewriter.StartTagData(name, _)) -> Ok([name])
    rewriter.ParentStart(_, rewriter.StartTagData(name, _)) -> Ok([name])
    any -> Error(UnexpectedTokenError(any))
  }
}

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
  case start, tokens {
    rewriter.Clearance(_, rewriter.Clears(_)),
      [rewriter.Indent(_), rewriter.Leading(_, lexeme), ..]
    -> Some(lexeme)
    _, _ -> None
  }
}

fn extrinsic_indentation(start, end) {
  case standalone(start, end), start {
    True, rewriter.Clearance(rewriter.Clears(leading), _) -> leading
    _, _ -> None
  }
}

fn deindent(
  intrinsic_indentation: Option(String),
  expressions: List(Expression),
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
    [Leading(indentation), ..tail] ->
      case string.drop_start(indentation, string.length(by)) {
        "" -> deindent_loop(tail, by, acc)
        indentation -> deindent_loop(tail, by, [Leading(indentation), ..acc])
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
    [StandaloneParameter(name, indentation, content), ..tail] ->
      deindent_loop(tail, by, [
        StandaloneParameter(
          name,
          option.map(indentation, string.drop_start(_, string.length(by))),
          deindent_loop(content, by, []),
        ),
        ..acc
      ])
    [StandaloneParent(name, indentation, content), ..tail] ->
      deindent_loop(tail, by, [
        StandaloneParent(
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

fn insert_end_tag_clearance(
  acc: List(Expression),
  clearance: rewriter.Clearance,
) -> List(Expression) {
  case clearance {
    // standalone, so we elide the whole line
    rewriter.Clearance(rewriter.Clears(_), rewriter.Clears(_)) -> acc
    // otherwise, we extract the whitespace in the clearance
    rewriter.Clearance(start, end) -> {
      let leading = case start {
        rewriter.Clears(leading) -> leading
        _ -> None
      }
      let trailing = case end {
        rewriter.Clears(trailing) -> trailing
        _ -> None
      }
      let acc = case leading {
        None -> acc
        Some(leading) -> [Leading(leading), ..acc]
      }
      case trailing {
        None -> acc
        Some(trailing) -> [Literal(trailing), ..acc]
      }
    }
  }
}

fn ensure_indent(expressions: List(Expression)) -> List(Expression) {
  case expressions {
    [Indent, ..] -> expressions
    _ -> [Indent, ..expressions]
  }
}

fn remove_indent(expressions: List(Expression)) -> List(Expression) {
  case expressions {
    [Indent, ..tail] -> tail
    expressions -> expressions
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
