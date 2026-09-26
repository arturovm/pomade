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
    [scanner.Eof] | [scanner.End(_), ..] -> Ok(#(list.reverse(acc), tokens))
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
    [scanner.ParentStart(_), ..] ->
      parse_enclosed(tokens, parse_parent_opening, Parent)
    _ -> parse_block(tokens)
  }
}

fn parse_parent_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.ParentStart(path), ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_block(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.BlockStart(_), ..] ->
      parse_enclosed(tokens, parse_block_opening, Block)
    _ -> parse_inverted_section(tokens)
  }
}

fn parse_block_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.BlockStart(path), ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_inverted_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.InvertedSectionStart(_), ..] ->
      parse_enclosed(tokens, parse_inverted_section_opening, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.InvertedSectionStart(path), ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.SectionStart(_), ..] ->
      parse_enclosed(tokens, parse_section_opening, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.SectionStart(path), ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_closing_tag(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.End(path), ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_partial(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Partial(path), ..tail] -> {
      Ok(emit_expr(Partial, path, tail))
    }
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.RawVariable(path), ..tail] ->
      Ok(emit_expr(RawVariable, path, tail))
    _ -> parse_variable(tokens)
  }
}

fn parse_variable(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Variable(path), ..tail] -> Ok(emit_expr(Variable, path, tail))

    _ -> parse_primary(tokens)
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
