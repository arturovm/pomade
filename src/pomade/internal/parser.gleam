//// Mustache syntactical grammar:
////
//// template                 -> expressions ;
//// expressions              -> expression* ;
//// expression               -> TEXT | NEWLINE | variable | raw_variable | section | inverted_section | partial | block | parent ;
//// variable                 -> LEFT_DELIMITER name RIGHT_DELIMITER ;
//// raw_variable             -> ("{{{" name "}}}") | (LEFT_DELIMITER "&" name RIGHT_DELIMITER) ;
//// section                  -> section_opening expressions closing_tag ;
//// section_opening          -> LEFT_DELIMITER "#" name RIGHT_DELIMITER ;
//// inverted_section         -> inverted_section_opening expressions closing_tag ;
//// inverted_section_opening -> LEFT_DELIMITER "^" name RIGHT_DELIMITER ;
//// partial                  -> LEFT_DELIMITER ">" name RIGHT_DELIMITER ;
//// block                    -> block_opening expressions closing_tag ;
//// block_opening            -> LEFT_DELIMITER "$" name RIGHT_DELIMITER ;
//// parent                   -> parent_opening expressions closing_tag ;
//// parent_opening           -> LEFT_DELIMITER "<" name RIGHT_DELIMITER ;
//// closing_tag              -> LEFT_DELIMITER "/" name RIGHT_DELIMITER ;
//// name                     -> "." | (IDENTIFIER? ("." IDENTIFIER)*)) ;

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result

import pomade/internal/scanner.{type Token}

pub type Template {
  Template(List(Expression))
}

pub type Expression {
  Text(value: String)
  Newline(value: String)
  Variable(path: List(String))
  RawVariable(path: List(String))
  Section(path: List(String), content: List(Expression))
  InvertedSection(path: List(String), content: List(Expression))
  Partial(name: List(String))
  Block(path: List(String), content: List(Expression))
  Parent(path: List(String), content: List(Expression))
}

pub type SyntaxError {
  SyntaxError
  UnexpectedTokenError(Token)
  ExpectedExpressionError
  ExpectedMoreTokensError
  NoMatchingClosingTagError
}

pub fn parse(tokens: List(Token)) -> Result(Template, SyntaxError) {
  template(tokens)
}

// rules

fn template(tokens: List(Token)) -> Result(Template, SyntaxError) {
  use #(expressions, _) <- result.map(expressions(tokens, []))
  Template(expressions)
}

fn expressions(
  tokens: List(Token),
  acc: List(Expression),
) -> Result(#(List(Expression), List(Token)), SyntaxError) {
  case tokens {
    [] -> Ok(#(list.reverse(acc), []))
    [scanner.LeftDelimiter, scanner.ClosingIndicator, ..] ->
      Ok(#(list.reverse(acc), tokens))
    non_empty -> {
      use #(expression, tail) <- result.try(expression(non_empty))
      let acc = case expression {
        None -> acc
        Some(expression) -> list.prepend(acc, expression)
      }
      expressions(tail, acc)
    }
  }
}

fn expression(
  tokens: List(Token),
) -> Result(#(Option(Expression), List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftTripleMustache, ..]
    | [scanner.LeftDelimiter, scanner.RawVariableIndicator, ..] ->
      map_expr(tokens, raw_variable)
    [scanner.LeftDelimiter, scanner.SectionIndicator, ..] ->
      map_expr(tokens, section)
    [scanner.LeftDelimiter, scanner.InvertedSectionIndicator, ..] ->
      map_expr(tokens, inverted_section)
    [scanner.LeftDelimiter, scanner.PartialIndicator, ..] ->
      map_expr(tokens, partial)
    [scanner.LeftDelimiter, scanner.BlockIndicator, ..] ->
      map_expr(tokens, block)
    [scanner.LeftDelimiter, scanner.ParentIndicator, ..] ->
      map_expr(tokens, parent)
    [scanner.LeftDelimiter, ..] -> map_expr(tokens, variable)
    [scanner.Text(_), scanner.Ignored, scanner.Newline(_), ..] ->
      check_comment(tokens)
    [scanner.Ignored, ..tail] -> Ok(#(None, tail))
    [scanner.Newline(value), ..tail] -> Ok(#(Some(Newline(value)), tail))
    [scanner.Text(value), ..tail] -> Ok(#(Some(Text(value)), tail))
    _ -> Error(ExpectedExpressionError)
  }
}

fn map_expr(
  tokens: List(Token),
  rule: fn(List(Token)) -> Result(#(Expression, List(Token)), SyntaxError),
) -> Result(#(Option(Expression), List(Token)), SyntaxError) {
  use res <- result.map(rule(tokens))
  pair.map_first(res, Some)
}

fn variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect(tokens, scanner.LeftDelimiter))
  let #(path, tail) = name(tail)
  use #(_, tail) <- result.map(expect(tail, scanner.RightDelimiter))
  #(Variable(path), tail)
}

fn raw_variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftTripleMustache, ..] -> {
      raw_variable_with_triple_mustache(tokens)
    }
    [scanner.LeftDelimiter, ..] -> raw_variable_with_delimiters(tokens)
    _ -> Error(SyntaxError)
  }
}

fn raw_variable_with_triple_mustache(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect(tokens, scanner.LeftTripleMustache))
  let #(path, tail) = name(tail)
  use #(_, tail) <- result.map(expect(tail, scanner.RightTripleMustache))
  #(RawVariable(path), tail)
}

fn raw_variable_with_delimiters(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    scanner.RawVariableIndicator,
  ))
  #(RawVariable(path), tail)
}

fn section(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  parse_enclosed(tokens, section_opening, Section)
}

fn section_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.SectionIndicator)
}

fn closing_tag(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    scanner.ClosingIndicator,
  ))
  #(path, tail)
}

fn inverted_section(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  parse_enclosed(tokens, inverted_section_opening, InvertedSection)
}

fn inverted_section_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.InvertedSectionIndicator)
}

fn partial(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    scanner.PartialIndicator,
  ))
  #(Partial(path), tail)
}

fn block(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  parse_enclosed(tokens, block_opening, Block)
}

fn block_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.BlockIndicator)
}

fn parent(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  parse_enclosed(tokens, parent_opening, Parent)
}

fn parent_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.ParentIndicator)
}

fn name(tokens: List(Token)) -> #(List(String), List(Token)) {
  case tokens {
    [scanner.Dot, ..tail] -> #(["."], tail)
    [scanner.Identifier(value), ..tail] -> {
      name_loop(tail, [value])
    }
    _ -> #([], tokens)
  }
}

fn name_loop(
  tokens: List(Token),
  path: List(String),
) -> #(List(String), List(Token)) {
  case tokens {
    [scanner.Dot, scanner.Identifier(value), ..tail] ->
      name_loop(tail, list.prepend(path, value))
    any -> {
      #(list.reverse(path), any)
    }
  }
}

// helpers

fn parse_tag_with_indicator(
  tokens: List(Token),
  indicator: Token,
) -> Result(#(List(String), List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect(tokens, scanner.LeftDelimiter))
  use #(_, tail) <- result.try(expect(tail, indicator))
  let #(path, tail) = name(tail)
  use #(_, tail) <- result.map(expect(tail, scanner.RightDelimiter))
  #(path, tail)
}

fn parse_enclosed(
  tokens: List(Token),
  opening_rule: fn(List(Token)) ->
    Result(#(List(String), List(Token)), SyntaxError),
  expr_constructor: fn(List(String), List(Expression)) -> Expression,
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(path, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(expressions(tail, []))
  use #(closing_path, tail) <- result.try(closing_tag(tail))
  case path == closing_path {
    False -> Error(NoMatchingClosingTagError)
    True -> Ok(#(expr_constructor(path, expressions), tail))
  }
}

fn check_comment(tokens) {
  case tokens {
    [scanner.Text(content), scanner.Ignored, scanner.Newline(_), ..tail] -> {
      case is_blank(content) {
        False -> Ok(#(Some(Text(content)), tail))
        True -> Ok(#(None, tail))
      }
    }
    _ -> Error(SyntaxError)
  }
}

fn is_blank(string: String) -> Bool {
  case string {
    "" -> True
    " " <> tail | "\t" <> tail -> is_blank(tail)
    _ -> False
  }
}

fn expect(
  tokens: List(Token),
  expected: Token,
) -> Result(#(Token, List(Token)), SyntaxError) {
  case tokens {
    [head, ..tail] ->
      case head == expected {
        True -> Ok(#(head, tail))
        False -> Error(UnexpectedTokenError(head))
      }
    [] -> Error(ExpectedMoreTokensError)
  }
}
