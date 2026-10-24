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
  Section(path: List(String), end: rewriter.Element, content: List(Expression))
  InvertedSection(
    path: List(String),
    end: rewriter.Element,
    content: List(Expression),
  )
  Partial(name: scanner.PartialName, indentation: Option(String))
  // block parameter
  Parameter(
    start: rewriter.Element,
    end: rewriter.Element,
    indentation: Option(String),
    content: List(Expression),
  )
  Parent(
    start: rewriter.Element,
    end: rewriter.Element,
    indentation: Option(String),
    content: List(Expression),
  )
  // block argument
  Argument(
    start: rewriter.Element,
    end: rewriter.Element,
    indentation: Option(String),
    content: List(Expression),
  )
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
        Ok(#(Some(some), tail)) -> parse_expressions(tail, [some, ..acc])
        Ok(#(None, tail)) -> parse_expressions(tail, acc)
        Error(error) -> Error(error)
      }
  }
}

fn parse_expression(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  parse_indent(tokens)
}

fn parse_indent(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Indent(_), ..tail] -> Ok(#(Some(Indent), tail))
    _ -> parse_leading(tokens)
  }
}

fn parse_leading(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Leading(_, lexeme), ..tail] -> Ok(#(Some(Leading(lexeme)), tail))
    _ -> parse_parameter(tokens)
  }
}

fn parse_parameter(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.BlockStart(_, _, _) as start, ..tail] ->
      parse_parameter_content(tail, start)
    _ -> parse_parent(tokens)
  }
}

fn parse_parameter_content(
  tokens: List(rewriter.Element),
  start: rewriter.Element,
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, []))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True -> {
      let standalone = case start, end {
        rewriter.BlockStart(_, _, rewriter.Clearance(rewriter.Clears(_), _)),
          rewriter.End(_, _, rewriter.Clearance(_, rewriter.Clears(_)))
        -> True
        _, _ -> False
      }
      let intrinsic_indentation = case standalone, tokens {
        True, [rewriter.Indent(_), rewriter.Leading(_, lexeme), ..] ->
          Some(lexeme)
        _, _ -> None
      }
      let deindented_expressions = case intrinsic_indentation {
        None -> expressions
        Some(intrinsic_indentation) ->
          deindent(expressions, intrinsic_indentation, [])
      }
      Ok(#(
        Some(Parameter(
          start,
          end,
          intrinsic_indentation,
          deindented_expressions,
        )),
        tail,
      ))
    }
  }
}

fn deindent(
  expressions: List(Expression),
  by: String,
  acc: List(Expression),
) -> List(Expression) {
  case expressions {
    [] -> list.reverse(acc)
    [Leading(indentation), ..tail] ->
      deindent(tail, by, [
        Leading(string.drop_start(indentation, string.length(by))),
        ..acc
      ])
    [Section(path, end, content), ..tail] ->
      deindent(tail, by, [Section(path, end, deindent(content, by, [])), ..acc])
    [InvertedSection(path, end, content), ..tail] ->
      deindent(tail, by, [
        InvertedSection(path, end, deindent(content, by, [])),
        ..acc
      ])
    [Parameter(start, end, indentation, content), ..tail] ->
      deindent(tail, by, [
        Parameter(start, end, indentation, deindent(content, by, [])),
        ..acc
      ])
    [Parent(start, end, indentation, content), ..tail] ->
      deindent(tail, by, [
        Parent(start, end, indentation, deindent(content, by, [])),
        ..acc
      ])
    [Argument(start, end, indentation, content), ..tail] ->
      deindent(tail, by, [
        Argument(start, end, indentation, deindent(content, by, [])),
        ..acc
      ])
    [expression, ..tail] -> deindent(tail, by, [expression, ..acc])
  }
}

fn parse_parent(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.ParentStart(_, _, _) as start, ..tail] ->
      parse_parent_content(tail, start, None)
    _ -> parse_inverted_section(tokens)
  }
}

fn parse_parent_content(
  tokens: List(rewriter.Element),
  start: rewriter.Element,
  indentation: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_arguments(tokens, []))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True -> Ok(#(Some(Parent(start, end, indentation, expressions)), tail))
  }
}

fn parse_arguments(
  tokens: List(rewriter.Element),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_)] | [rewriter.End(_, _, _), ..] ->
      Ok(#(list.reverse(acc), tokens))
    non_empty ->
      case parse_argument_or_discard_expression(non_empty) {
        Ok(#(Some(some), tail)) -> parse_arguments(tail, [some, ..acc])
        Ok(#(None, tail)) -> parse_arguments(tail, acc)
        Error(error) -> Error(error)
      }
  }
}

fn parse_argument_or_discard_expression(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.BlockStart(_, _, _) as start, ..tail] ->
      parse_argument_content(tail, start)
    other -> {
      case parse_expression(other) {
        Ok(#(_, tail)) -> Ok(#(None, tail))
        error -> error
      }
    }
  }
}

fn parse_argument_content(
  tokens: List(rewriter.Element),
  start: rewriter.Element,
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, []))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True -> Ok(#(Some(Argument(start, end, None, expressions)), tail))
  }
}

fn parse_inverted_section(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_inverted_section_opening, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_opening(
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
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_section_opening, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_opening(
  tokens: List(rewriter.Element),
) -> Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_closing_tag(
  tokens: List(rewriter.Element),
) -> Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.End(_, _, _) as end, ..tail] -> Ok(#(end, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_partial(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Partial(_, name, indentation), ..tail] ->
      Ok(#(Some(Partial(name, indentation)), tail))
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.RawVariable(_, path), ..tail] ->
      Ok(emit_expr(RawVariable, path, tail))
    _ -> parse_variable(tokens)
  }
}

fn parse_variable(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Variable(_, path), ..tail] -> Ok(emit_expr(Variable, path, tail))

    _ -> parse_primary(tokens)
  }
}

fn parse_primary(
  tokens: List(rewriter.Element),
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  case tokens {
    [rewriter.Literal(_, value), ..tail] -> Ok(#(Some(Literal(value)), tail))
    [rewriter.Eof(_)] -> Ok(#(None, tokens))
    [any, ..] -> Error(UnexpectedTokenError(any))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// helpers

fn parse_enclosed(
  tokens: List(rewriter.Element),
  opening_rule: fn(List(rewriter.Element)) ->
    Result(#(rewriter.Element, List(rewriter.Element)), SyntaxError),
  expr_constructor: fn(List(String), rewriter.Element, List(Expression)) ->
    Expression,
) -> Result(#(Option(Expression), List(rewriter.Element)), SyntaxError) {
  use #(start, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, []))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True -> Ok(#(Some(expr_constructor(start_path, end, expressions)), tail))
  }
}

fn tag_path(tag: rewriter.Element) -> Result(List(String), SyntaxError) {
  case tag {
    rewriter.SectionStart(_, path) -> Ok(path)
    rewriter.InvertedSectionStart(_, path) -> Ok(path)
    rewriter.End(_, path, _) -> Ok(path)
    rewriter.BlockStart(_, name, _) -> Ok([name])
    rewriter.ParentStart(_, name, _) -> Ok([name])
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

fn emit_expr(
  expression: fn(x) -> Expression,
  value: x,
  tail: List(rewriter.Element),
) -> #(Option(Expression), List(rewriter.Element)) {
  #(Some(expression(value)), tail)
}

fn remove_prefix(str: String, prefix: Option(String)) -> String {
  case prefix {
    Some(prefix) -> string.drop_start(str, string.length(prefix))
    None -> str
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
