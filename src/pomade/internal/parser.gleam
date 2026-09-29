//// Mustache syntactical grammar:
////
//// template                 -> {expression} EOF;
//// expression               -> Parent ;
//// Parent                   -> PARENT_START {expression} END | Block;
//// Block                    -> BLOCK_START {expression} END | InvertedSection ;
//// InvertedSection          -> INVERTED_SECTION_START {expression} END | Section;
//// Section                  -> SECTION_START {expression} END | Partial ;
//// Partial                  -> [INDENTATION] PARTIAL | RawVariable ;
//// RawVariable              -> (TRIPLE_MUSTACHE | RAW_VARIABLE) | Variable ;
//// Variable                 -> VARIABLE | Primary ;
//// Primary                  -> TEXT | WHITESPACE | NEWLINE

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import pomade/internal/scanner

pub type Expression {
  Text(token: scanner.Token)
  Whitespace(token: scanner.Token)
  Newline(token: scanner.Token)
  Variable(token: scanner.Token)
  RawVariable(token: scanner.Token)
  Section(token: scanner.Token, content: List(Expression))
  InvertedSection(token: scanner.Token, content: List(Expression))
  Partial(name: scanner.Token, indentation: Option(String))
}

/// `SyntaxError` represents an error encountered during parsing.
pub type SyntaxError {
  /// `UnexpectedTokenError` is returned when a token different from what the
  /// grammar indicates is found.
  UnexpectedTokenError(scanner.Token)
  /// `UnexpectedEndOfInputError` is used to report that more tokens were
  /// expected, but the parser unexpectedly consumed the whole input.
  UnexpectedEndOfInputError
  /// `NoMatchingClosingTagError` is returned when a `{{/closing_tag}}` was
  /// expected, but none was found.
  NoMatchingEndTagError(scanner.Token)
}

pub fn parse(
  tokens: List(scanner.Token),
) -> Result(List(Expression), SyntaxError) {
  parse_template(tokens)
}

// rules

fn parse_template(
  tokens: List(scanner.Token),
) -> Result(List(Expression), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, []))
  use _ <- result.map(parse_eof(tail))
  expressions
}

fn parse_expressions(
  tokens: List(scanner.Token),
  acc: List(Expression),
) -> Result(#(List(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Eof(_)] | [scanner.End(_, _), ..] ->
      Ok(#(list.reverse(acc), tokens))
    non_empty -> {
      use #(expression, tail) <- result.try(parse_expression(non_empty))
      let acc = case expression {
        Some(some) -> list.prepend(acc, some)
        None -> acc
      }
      parse_expressions(tail, acc)
    }
  }
}

fn parse_expression(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  parse_inverted_section(tokens)
}

fn parse_inverted_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.InvertedSectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_inverted_section_opening, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(scanner.Token, List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.InvertedSectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.SectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_section_opening, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(scanner.Token, List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.SectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_closing_tag(
  tokens: List(scanner.Token),
) -> Result(#(scanner.Token, List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.End(_, _) as end, ..tail] -> Ok(#(end, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_partial(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [
      scanner.Indentation(_, indentation),
      scanner.Partial(_, _) as token,
      ..tail
    ] -> Ok(#(Some(Partial(token, Some(indentation))), tail))
    [scanner.Partial(_, _) as name, ..tail] -> {
      Ok(#(Some(Partial(name, None)), tail))
    }
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.RawVariable(_, _) as path, ..tail] ->
      Ok(emit_expr(RawVariable, path, tail))
    _ -> parse_variable(tokens)
  }
}

fn parse_variable(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Variable(_, _) as path, ..tail] ->
      Ok(emit_expr(Variable, path, tail))

    _ -> parse_primary(tokens)
  }
}

fn parse_primary(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Text(_, _) as value, ..tail] -> Ok(emit_expr(Text, value, tail))
    [scanner.Whitespace(_, _) as value, ..tail] ->
      Ok(emit_expr(Whitespace, value, tail))
    [scanner.Newline(_, _) as value, ..tail] ->
      Ok(emit_expr(Newline, value, tail))
    [scanner.Eof(_)] -> Ok(#(None, tokens))
    [any, ..] -> Error(UnexpectedTokenError(any))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// helpers

fn parse_enclosed(
  tokens: List(scanner.Token),
  opening_rule: fn(List(scanner.Token)) ->
    Result(#(scanner.Token, List(scanner.Token)), SyntaxError),
  expr_constructor: fn(scanner.Token, List(Expression)) -> Expression,
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  use #(start, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, []))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  case start_tag_and_end_tag_match(start, end) {
    False -> Error(NoMatchingEndTagError(start))
    True -> Ok(#(Some(expr_constructor(start, expressions)), tail))
  }
}

fn start_tag_and_end_tag_match(start: scanner.Token, end: scanner.Token) {
  let assert scanner.End(_, end_path) = end
  case start {
    scanner.SectionStart(_, start_path) -> start_path == end_path
    scanner.InvertedSectionStart(_, start_path) -> start_path == end_path
    _ -> False
  }
}

fn parse_eof(
  tokens: List(scanner.Token),
) -> Result(#(scanner.Token, List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Eof(_) as eof] -> Ok(#(eof, tokens))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn emit_expr(
  expression: fn(x) -> Expression,
  value: x,
  tail: List(scanner.Token),
) -> #(Option(Expression), List(scanner.Token)) {
  #(Some(expression(value)), tail)
}

// formatting

pub fn error_to_string(error: SyntaxError) -> String {
  case error {
    UnexpectedTokenError(token) ->
      "line "
      <> int.to_string(token.line)
      <> ": unexpected token: "
      <> scanner.token_to_string(token)
    UnexpectedEndOfInputError -> "unexpected end of input"
    NoMatchingEndTagError(token) ->
      "line "
      <> int.to_string(token.line)
      <> ": no matching end tag found for start tag: "
      <> scanner.token_to_string(token)
  }
}
