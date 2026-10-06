//// Mustache syntactical grammar:
////
//// template                 -> {expression} EOF ;
//// expression               -> Parent ;
//// Parent                   -> PARENT_START {expression} END | Block ;
//// Block                    -> BLOCK_START {expression} END | InvertedSection ;
//// InvertedSection          -> INVERTED_SECTION_START {expression} END | Section;
//// Section                  -> SECTION_START {expression} END | Partial ;
//// Partial                  -> [INDENTATION] PARTIAL | RawVariable ;
//// RawVariable              -> (TRIPLE_MUSTACHE | RAW_VARIABLE) | Variable ;
//// Variable                 -> VARIABLE | Literal ;
//// Literal                  -> TEXT | WHITESPACE | NEWLINE ;

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import pomade/internal/rewriter

pub type Expression {
  Literal(token: rewriter.Token)
  Variable(token: rewriter.Token)
  RawVariable(token: rewriter.Token)
  Section(token: rewriter.Token, content: List(Expression))
  InvertedSection(token: rewriter.Token, content: List(Expression))
  Partial(name: rewriter.Token, indentation: Option(String))
}

/// `SyntaxError` represents an error encountered during parsing.
pub type SyntaxError {
  /// `UnexpectedTokenError` is returned when a token different from what the
  /// grammar indicates is found.
  UnexpectedTokenError(rewriter.Token)
  /// `UnexpectedEndOfInputError` is used to report that more tokens were
  /// expected, but the parser unexpectedly consumed the whole input.
  UnexpectedEndOfInputError
  /// `NoMatchingClosingTagError` is returned when a `{{/closing_tag}}` was
  /// expected, but none was found.
  NoMatchingEndTagError(rewriter.Token)
}

pub fn parse(
  tokens: List(rewriter.Token),
) -> Result(List(Expression), SyntaxError) {
  parse_template(tokens)
}

// rules

fn parse_template(
  tokens: List(rewriter.Token),
) -> Result(List(Expression), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, []))
  use _ <- result.map(parse_eof(tail))
  expressions
}

fn parse_expressions(
  tokens: List(rewriter.Token),
  acc: List(Expression),
) -> Result(#(List(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_)] | [rewriter.End(_, _), ..] ->
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
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  parse_inverted_section(tokens)
}

fn parse_inverted_section(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_inverted_section_opening, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_opening(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_section(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_section_opening, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_opening(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_closing_tag(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.End(_, _) as end, ..tail] -> Ok(#(end, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_partial(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [
      rewriter.Indentation(_, indentation),
      rewriter.Partial(_, _) as token,
      ..tail
    ] -> Ok(#(Some(Partial(token, Some(indentation))), tail))
    [rewriter.Partial(_, _) as name, ..tail] -> {
      Ok(#(Some(Partial(name, None)), tail))
    }
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.RawVariable(_, _) as path, ..tail] ->
      Ok(emit_expr(RawVariable, path, tail))
    _ -> parse_variable(tokens)
  }
}

fn parse_variable(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Variable(_, _) as path, ..tail] ->
      Ok(emit_expr(Variable, path, tail))

    _ -> parse_primary(tokens)
  }
}

fn parse_primary(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Literal(_, _) as value, ..tail] ->
      Ok(#(Some(Literal(value)), tail))
    [rewriter.Eof(_)] -> Ok(#(None, tokens))
    [any, ..] -> Error(UnexpectedTokenError(any))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// helpers

fn parse_enclosed(
  tokens: List(rewriter.Token),
  opening_rule: fn(List(rewriter.Token)) ->
    Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError),
  expr_constructor: fn(rewriter.Token, List(Expression)) -> Expression,
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  use #(start, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, []))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True -> Ok(#(Some(expr_constructor(start, expressions)), tail))
  }
}

fn tag_path(tag: rewriter.Token) -> Result(List(String), SyntaxError) {
  case tag {
    rewriter.SectionStart(_, path) -> Ok(path)
    rewriter.InvertedSectionStart(_, path) -> Ok(path)
    rewriter.End(_, path) -> Ok(path)
    any -> Error(UnexpectedTokenError(any))
  }
}

fn parse_eof(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_) as eof] -> Ok(#(eof, tokens))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn emit_expr(
  expression: fn(x) -> Expression,
  value: x,
  tail: List(rewriter.Token),
) -> #(Option(Expression), List(rewriter.Token)) {
  #(Some(expression(value)), tail)
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
