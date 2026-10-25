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
import pomade/internal/scanner

import pomade/internal/rewriter

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
  Section(
    path: List(String),
    end: rewriter.Clearance,
    content: List(Expression),
  )
  InvertedSection(
    path: List(String),
    end: rewriter.Clearance,
    content: List(Expression),
  )
  Partial(name: scanner.PartialName, indentation: Option(String))
  // block parameter
  Parameter(
    name: String,
    start: rewriter.Clearance,
    end: rewriter.Clearance,
    indentation: Option(String),
    content: List(Expression),
  )
  Parent(
    name: String,
    start_clearance: rewriter.Clearance,
    end_clearance: rewriter.Clearance,
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
  use _ <- result.map(parse_eof(tail))
  expressions
}

fn parse_expressions(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_)] | [rewriter.End(_, _, _), ..] ->
      Ok(#(list.reverse(acc), tokens))
    non_empty ->
      case parse_expression(non_empty) {
        Ok(#(expr, tail)) -> parse_expressions(tail, [expr, ..acc])
        Error(error) -> Error(error)
      }
  }
}

fn parse_expression(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  parse_indent(tokens)
}

fn parse_indent(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Indent(_), ..tail] -> Ok(#(Indent, tail))
    _ -> parse_leading(tokens)
  }
}

fn parse_leading(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Leading(_, lexeme), ..tail] -> Ok(#(Leading(lexeme), tail))
    _ -> parse_parameter(tokens)
  }
}

fn parse_parameter(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.BlockStart(_, data) as tag, ..tail] -> {
      use #(expressions, tail) <- result.try(parse_expressions(tail, []))
      use #(end, tail) <- result.map(parse_end_tag(tail, tag, [data.name]))
      let intrinsic_indentation = case standalone(data.clearance, end) {
        True -> intrinsic_indentation(data.clearance, tokens)
        False -> None
      }
      let deindented_expressions = deindent(intrinsic_indentation, expressions)
      #(
        Parameter(
          data.name,
          data.clearance,
          end,
          intrinsic_indentation,
          deindented_expressions,
        ),
        tail,
      )
    }
    _ -> parse_parent(tokens)
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
      deindent_loop(tail, by, [
        Leading(string.drop_start(indentation, string.length(by))),
        ..acc
      ])
    [Section(path, end, content), ..tail] ->
      deindent_loop(tail, by, [
        Section(path, end, deindent_loop(content, by, [])),
        ..acc
      ])
    [InvertedSection(path, end, content), ..tail] ->
      deindent_loop(tail, by, [
        InvertedSection(path, end, deindent_loop(content, by, [])),
        ..acc
      ])
    [Parameter(name, start, end, indentation, content), ..tail] ->
      deindent_loop(tail, by, [
        Parameter(name, start, end, indentation, deindent_loop(content, by, [])),
        ..acc
      ])
    [Parent(name, start, end, indentation, content), ..tail] ->
      deindent_loop(tail, by, [
        Parent(
          name,
          start,
          end,
          indentation,
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

fn parse_parent(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.ParentStart(_, data) as tag, ..tail] -> {
      use #(expressions, tail) <- result.try(parse_arguments(tail, []))
      use #(end_clearance, tail) <- result.map(
        parse_end_tag(tail, tag, [data.name]),
      )
      #(
        Parent(data.name, data.clearance, end_clearance, None, expressions),
        tail,
      )
    }
    _ -> parse_inverted_section(tokens)
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
      case parse_expression(other) {
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
  use #(expressions, tail) <- result.try(parse_expressions(tokens, []))
  use #(_, tail) <- result.map(parse_end_tag(tail, start, [data.name]))
  let intrinsic_indentation = intrinsic_indentation(data.clearance, tokens)
  let deindented_expressions = deindent(intrinsic_indentation, expressions)
  #(Argument(data.name, deindented_expressions), tail)
}

fn parse_inverted_section(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_inverted_section_start, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_start(
  tokens: List(rewriter.Element),
) -> Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_section(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_section_start, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_start(
  tokens: List(rewriter.Element),
) -> Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
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
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Partial(_, name, indentation), ..tail] ->
      Ok(#(Partial(name, indentation), tail))
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.RawVariable(_, path), ..tail] -> Ok(#(RawVariable(path), tail))
    _ -> parse_variable(tokens)
  }
}

fn parse_variable(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Variable(_, path), ..tail] -> Ok(#(Variable(path), tail))

    _ -> parse_primary(tokens)
  }
}

fn parse_primary(
  tokens: List(rewriter.Element),
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Literal(_, value), ..tail] -> Ok(#(Literal(value), tail))
    [any, ..] -> Error(UnexpectedTokenError(any))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// helpers

fn parse_enclosed(
  tokens: List(rewriter.Element),
  opening_rule: fn(List(rewriter.Element)) ->
    Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError),
  expr_constructor: fn(List(String), rewriter.Clearance, List(Expression)) ->
    Expression,
) -> Result(#(Expression, List(rewriter.Element)), SyntaxError) {
  use #(start, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, []))
  use start_path <- result.try(tag_path(start))
  use #(end, tail) <- result.map(parse_end_tag(tail, start, start_path))
  #(expr_constructor(start_path, end, expressions), tail)
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

fn parse_eof(
  tokens: List(rewriter.Element),
) -> Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_) as eof] -> Ok(#(eof, tokens))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
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
