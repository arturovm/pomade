//// Mustache syntactical grammar:
////
//// template                 -> expression* EOF ;
//// expression               -> parent
//// parent                   -> parent_opening expression* closing_tag | block;
//// parent_opening           -> LEFT_DELIMITER "<" name RIGHT_DELIMITER ;
//// block                    -> block_opening expression* closing_tag | inverted_section ;
//// block_opening            -> LEFT_DELIMITER "$" name RIGHT_DELIMITER ;
//// inverted_section         -> inverted_section_opening expression* closing_tag | section;
//// inverted_section_opening -> LEFT_DELIMITER "^" name RIGHT_DELIMITER ;
//// section                  -> section_opening expression* closing_tag | partial ;
//// section_opening          -> LEFT_DELIMITER "#" name RIGHT_DELIMITER ;
//// closing_tag              -> LEFT_DELIMITER "/" name RIGHT_DELIMITER ;
//// partial                  -> LEFT_DELIMITER ">" name RIGHT_DELIMITER | raw_variable ;
//// raw_variable             -> ("{{{" name "}}}") | (LEFT_DELIMITER "&" name RIGHT_DELIMITER) | variable ;
//// variable                 -> LEFT_DELIMITER name RIGHT_DELIMITER | primary ;
//// name                     -> "." | (IDENTIFIER? ("." IDENTIFIER)*)) ;
//// primary                  -> TEXT | NEWLINE

import gleam/list
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
  Partial(path: List(String))
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
  use #(expressions, tail) <- result.try(expressions(tokens, []))
  use _ <- result.map(expect(tail, scanner.Eof))
  Template(expressions)
}

fn expressions(
  tokens: List(Token),
  acc: List(Expression),
) -> Result(#(List(Expression), List(Token)), SyntaxError) {
  case tokens {
    [scanner.Eof] -> Ok(#(list.reverse(acc), tokens))
    [scanner.LeftDelimiter, scanner.ClosingIndicator, ..] ->
      Ok(#(list.reverse(acc), tokens))
    non_empty -> {
      use #(expression, tail) <- result.try(expression(non_empty))
      expressions(tail, list.prepend(acc, expression))
    }
  }
}

fn expression(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  parent(tokens)
}

fn parent(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.ParentIndicator, ..] ->
      parse_enclosed(tokens, parent_opening, Parent)
    _ -> block(tokens)
  }
}

fn parent_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.ParentIndicator)
}

fn block(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.BlockIndicator, ..] ->
      parse_enclosed(tokens, block_opening, Block)
    _ -> inverted_section(tokens)
  }
}

fn block_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.BlockIndicator)
}

fn inverted_section(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.InvertedSectionIndicator, ..] ->
      parse_enclosed(tokens, inverted_section_opening, InvertedSection)
    _ -> section(tokens)
  }
}

fn inverted_section_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.InvertedSectionIndicator)
}

fn section(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.SectionIndicator, ..] ->
      parse_enclosed(tokens, section_opening, Section)
    _ -> partial(tokens)
  }
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

fn partial(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.PartialIndicator, ..] -> {
      use #(path, tail) <- result.map(parse_tag_with_indicator(
        tokens,
        scanner.PartialIndicator,
      ))
      #(Partial(path), tail)
    }
    _ -> raw_variable(tokens)
  }
}

fn raw_variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftTripleMustache, ..] -> {
      raw_variable_with_triple_mustache(tokens)
    }
    [scanner.LeftDelimiter, scanner.RawVariableIndicator, ..] ->
      raw_variable_with_delimiters(tokens)
    _ -> variable(tokens)
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

fn variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, ..] -> {
      use #(_, tail) <- result.try(expect(tokens, scanner.LeftDelimiter))
      let #(path, tail) = name(tail)
      use #(_, tail) <- result.map(expect(tail, scanner.RightDelimiter))
      #(Variable(path), tail)
    }
    _ -> primary(tokens)
  }
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

fn primary(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.Text(value), scanner.Ignored, scanner.Newline(_), ..tail] -> {
      case is_blank(value) {
        True -> primary(tail)
        False -> Ok(#(Text(value), list.drop(tokens, 1)))
      }
    }
    [scanner.Ignored, ..tail] -> primary(tail)
    [scanner.Text(value), ..tail] -> Ok(#(Text(value), tail))
    [scanner.Newline(value), ..tail] -> Ok(#(Newline(value), tail))
    _ -> Error(ExpectedExpressionError)
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
