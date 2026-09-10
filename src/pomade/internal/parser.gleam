//// Mustache syntactical grammar:
////
//// template                 -> expressions ;
//// expressions              -> expression* ;
//// expression               -> TEXT | variable | raw_variable | section | inverted_section | partial | block | parent ;
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
import gleam/result

import pomade/internal/scanner.{type Token}

pub type Template {
  Template(List(Expression))
}

pub type Expression {
  Text(value: String)
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
  NonMatchingClosingTagError
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
    [scanner.LeftDelimiter(_), scanner.ClosingTag(_), ..] ->
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
  case tokens {
    [scanner.Text(_, value), ..tail] -> Ok(#(Text(value), tail))
    [scanner.LeftTripleMustache(_), ..]
    | [scanner.LeftDelimiter(_), scanner.RawVariable(_), ..] ->
      raw_variable(tokens)
    [scanner.LeftDelimiter(_), scanner.SectionStart(_), ..] -> section(tokens)
    [scanner.LeftDelimiter(_), scanner.InvertedSectionStart(_), ..] ->
      inverted_section(tokens)
    [scanner.LeftDelimiter(_), scanner.Partial(_), ..] -> partial(tokens)
    [scanner.LeftDelimiter(_), scanner.BlockStart(_), ..] -> block(tokens)
    [scanner.LeftDelimiter(_), scanner.ParentStart(_), ..] -> parent(tokens)
    [scanner.LeftDelimiter(_), ..] -> variable(tokens)
    _ -> Error(SyntaxError)
  }
}

fn variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect(tokens, is_left_delimiter))
  let #(path, tail) = name(tail)
  use #(_, tail) <- result.map(expect(tail, is_right_delimiter))
  #(Variable(path), tail)
}

fn raw_variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [scanner.LeftTripleMustache(_), ..] -> {
      raw_variable_with_triple_mustache(tokens)
    }
    [scanner.LeftDelimiter(_), ..] -> raw_variable_with_delimiters(tokens)
    _ -> Error(SyntaxError)
  }
}

fn raw_variable_with_triple_mustache(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect(tokens, is_left_triple_mustache))
  let #(path, tail) = name(tail)
  use #(_, tail) <- result.map(expect(tail, is_right_triple_mustache))
  #(RawVariable(path), tail)
}

fn raw_variable_with_delimiters(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    is_raw_variable,
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
  parse_tag_with_indicator(tokens, is_section_start)
}

fn closing_tag(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    is_closing_tag,
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
  parse_tag_with_indicator(tokens, is_inverted_section_start)
}

fn partial(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(tokens, is_partial))
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
  parse_tag_with_indicator(tokens, is_block)
}

fn parent(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  parse_enclosed(tokens, parent_opening, Parent)
}

fn parent_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, is_parent)
}

fn name(tokens: List(Token)) -> #(List(String), List(Token)) {
  case tokens {
    [scanner.Dot(_), ..tail] -> #(["."], tail)
    [scanner.Identifier(_, value), ..tail] -> {
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
    [scanner.Dot(_), scanner.Identifier(_, value), ..tail] ->
      name_loop(tail, list.prepend(path, value))
    any -> {
      #(list.reverse(path), any)
    }
  }
}

// helpers

fn parse_tag_with_indicator(
  tokens: List(Token),
  indicator: fn(Token) -> Bool,
) -> Result(#(List(String), List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect(tokens, is_left_delimiter))
  use #(_, tail) <- result.try(expect(tail, indicator))
  let #(path, tail) = name(tail)
  use #(_, tail) <- result.map(expect(tail, is_right_delimiter))
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
    False -> Error(NonMatchingClosingTagError)
    True -> Ok(#(expr_constructor(path, expressions), tail))
  }
}

// matchers

fn expect(
  tokens: List(Token),
  pred: fn(Token) -> Bool,
) -> Result(#(Token, List(Token)), SyntaxError) {
  case tokens {
    [head, ..tail] ->
      case pred(head) {
        True -> Ok(#(head, tail))
        False -> Error(UnexpectedTokenError(head))
      }
    [] -> Error(SyntaxError)
  }
}

fn is_left_delimiter(token: Token) -> Bool {
  case token {
    scanner.LeftDelimiter(_) -> True
    _ -> False
  }
}

fn is_right_delimiter(token: Token) -> Bool {
  case token {
    scanner.RightDelimiter(_) -> True
    _ -> False
  }
}

fn is_left_triple_mustache(token: Token) -> Bool {
  case token {
    scanner.LeftTripleMustache(_) -> True
    _ -> False
  }
}

fn is_right_triple_mustache(token: Token) -> Bool {
  case token {
    scanner.RightTripleMustache(_) -> True
    _ -> False
  }
}

fn is_raw_variable(token: Token) -> Bool {
  case token {
    scanner.RawVariable(_) -> True
    _ -> False
  }
}

fn is_section_start(token: Token) -> Bool {
  case token {
    scanner.SectionStart(_) -> True
    _ -> False
  }
}

fn is_inverted_section_start(token: Token) -> Bool {
  case token {
    scanner.InvertedSectionStart(_) -> True
    _ -> False
  }
}

fn is_partial(token: Token) -> Bool {
  case token {
    scanner.Partial(_) -> True
    _ -> False
  }
}

fn is_block(token: Token) -> Bool {
  case token {
    scanner.BlockStart(_) -> True
    _ -> False
  }
}

fn is_parent(token: Token) -> Bool {
  case token {
    scanner.ParentStart(_) -> True
    _ -> False
  }
}

fn is_closing_tag(token: Token) -> Bool {
  case token {
    scanner.ClosingTag(_) -> True
    _ -> False
  }
}
