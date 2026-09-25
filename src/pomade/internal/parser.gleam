//// Mustache syntactical grammar:
////
//// template                 -> {expression} EOF;
//// expression               -> Parent ;
//// Parent                   -> PARENT_OPENING {expression} CLOSING_TAG | Block;
//// Block                    -> BLOCK_OPENING {expression} CLOSING_TAG | InvertedSection ;
//// InvertedSection          -> INVERTED_SECTION_OPENING {expression} CLOSING_TAG | Section;
//// Section                  -> SECTION_OPENING {expression} CLOSING_TAG | Partial ;
//// Partial                  -> PARTIAL | RawVariable ;
//// RawVariable              -> (TRIPLE_MUSTACHE | RAW_VARIABLE) | Variable ;
//// Variable                 -> VARIABLE | Primary ;
//// Primary                  -> TEXT | WHITESPACE | NEWLINE

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import pomade/internal/scanner

pub type Expression {
  Text(value: String)
  Whitespace(value: String)
  Newline(value: String)
  Variable(path: List(String))
  RawVariable(path: List(String))
  Section(path: List(String), content: List(Expression))
  InvertedSection(path: List(String), content: List(Expression))
  Partial(path: List(String))
  Block(path: List(String), content: List(Expression))
  Parent(path: List(String), content: List(Expression))
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
  NoMatchingClosingTagError
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
  use _ <- result.map(expect_token(tail, scanner.Eof))
  expressions
}

fn parse_expressions(
  tokens: List(scanner.Token),
  acc: List(Expression),
) -> Result(#(List(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Eof] | [scanner.LeftDelimiter, scanner.End, ..] ->
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
  parse_parent(tokens)
}

fn parse_parent(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.ParentStart, ..] ->
      parse_enclosed(tokens, parse_parent_opening, Parent)
    _ -> parse_block(tokens)
  }
}

fn parse_parent_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.ParentStart)
}

fn parse_block(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.BlockStart, ..] ->
      parse_enclosed(tokens, parse_block_opening, Block)
    _ -> parse_inverted_section(tokens)
  }
}

fn parse_block_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.BlockStart)
}

fn parse_inverted_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.InvertedSectionStart, ..] ->
      parse_enclosed(tokens, parse_inverted_section_opening, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.InvertedSectionStart)
}

fn parse_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.SectionStart, ..] ->
      parse_enclosed(tokens, parse_section_opening, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.SectionStart)
}

fn parse_closing_tag(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(tokens, scanner.End))
  #(path, tail)
}

fn parse_partial(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.Partial, ..] -> {
      use #(path, tail) <- result.map(parse_tag_with_indicator(
        tokens,
        scanner.Partial,
      ))
      emit_expr(Partial, path, tail)
    }
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftTripleMustache, ..] -> {
      parse_raw_variable_with_triple_mustache(tokens)
    }
    [scanner.LeftDelimiter, scanner.RawVariable, ..] ->
      parse_raw_variable_with_delimiters(tokens)
    _ -> parse_variable(tokens)
  }
}

fn parse_raw_variable_with_triple_mustache(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect_token(tokens, scanner.LeftTripleMustache))
  let #(path, tail) = parse_name(tail)
  use #(_, tail) <- result.map(expect_token(tail, scanner.RightTripleMustache))
  emit_expr(RawVariable, path, tail)
}

fn parse_raw_variable_with_delimiters(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    scanner.RawVariable,
  ))
  emit_expr(RawVariable, path, tail)
}

fn parse_variable(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, ..] -> {
      use #(_, tail) <- result.try(expect_token(tokens, scanner.LeftDelimiter))
      let #(path, tail) = parse_name(tail)
      use #(_, tail) <- result.map(expect_token(tail, scanner.RightDelimiter))
      emit_expr(Variable, path, tail)
    }
    _ -> parse_primary(tokens)
  }
}

fn parse_name(
  tokens: List(scanner.Token),
) -> #(List(String), List(scanner.Token)) {
  case tokens {
    [scanner.Dot, ..tail] -> #(["."], tail)
    [scanner.Identifier(value), ..tail] -> {
      name_loop(tail, [value])
    }
    _ -> #([], tokens)
  }
}

fn name_loop(
  tokens: List(scanner.Token),
  path: List(String),
) -> #(List(String), List(scanner.Token)) {
  case tokens {
    [scanner.Dot, scanner.Identifier(value), ..tail] ->
      name_loop(tail, list.prepend(path, value))
    any -> {
      #(list.reverse(path), any)
    }
  }
}

fn parse_primary(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Text(value), ..tail] -> Ok(emit_expr(Text, value, tail))
    [scanner.Whitespace(value), ..tail] ->
      Ok(emit_expr(Whitespace, value, tail))
    [scanner.Newline(value), ..tail] -> Ok(emit_expr(Newline, value, tail))
    [scanner.Eof] -> Ok(#(None, tokens))
    _ -> Ok(#(None, tokens))
  }
}

// helpers

fn parse_tag_with_indicator(
  tokens: List(scanner.Token),
  indicator: scanner.Token,
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect_token(tokens, scanner.LeftDelimiter))
  use #(_, tail) <- result.try(expect_token(tail, indicator))
  let #(path, tail) = parse_name(tail)
  use #(_, tail) <- result.map(expect_token(tail, scanner.RightDelimiter))
  #(path, tail)
}

fn parse_enclosed(
  tokens: List(scanner.Token),
  opening_rule: fn(List(scanner.Token)) ->
    Result(#(List(String), List(scanner.Token)), SyntaxError),
  expr_constructor: fn(List(String), List(Expression)) -> Expression,
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  use #(path, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, []))
  use #(closing_path, tail) <- result.try(parse_closing_tag(tail))
  case path == closing_path {
    False -> Error(NoMatchingClosingTagError)
    True -> Ok(#(Some(expr_constructor(path, expressions)), tail))
  }
}

fn expect_token(
  tokens: List(scanner.Token),
  expected: scanner.Token,
) -> Result(#(scanner.Token, List(scanner.Token)), SyntaxError) {
  case tokens {
    [head, ..tail] ->
      case head == expected {
        True -> Ok(#(head, tail))
        False -> Error(UnexpectedTokenError(head))
      }
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
