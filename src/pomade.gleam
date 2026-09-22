import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string_tree.{type StringTree}
import houdini

import pomade/internal/scanner

/// `Template` represents a compiled template. Since this is a type alias to a
/// function, simply pass it a dictionary of input values.
pub type Template =
  fn(Value) -> Result(String, Error)

/// `Error` aggregates all the possible error types that can be emitted by the
/// different rendering phases.
pub type Error {
  /// `ScannerError` reports a lexical error, encountered during scanning.
  ScannerError(scanner.LexicalError)
  /// `ParserError` reports a syntax error, encountered during parsing.
  ParserError(SyntaxError)
  /// `InterpreterError` reports a runtime error, encountered during interpreting.
  InterpreterError(RuntimeError)
}

/// `render` renders a template source string directly. Useful when convenience
/// is the priority.
pub fn render(template: String, environment: Value) -> String {
  case scanner.scan(template) {
    Error(_) -> ""
    Ok(tokens) ->
      case parse(tokens) {
        Error(_) -> ""
        Ok(ast) ->
          case interpret(ast, environment) {
            Error(_) -> ""
            Ok(result) -> result
          }
      }
  }
}

/// `compile` prepares a template for future application, to avoid the overhead
/// of scanning and parsing a template from scratch every time. Prefer this
/// when speed is important.
pub fn compile(template: String) -> Result(Template, Error) {
  use tokens <- result.try(
    scanner.scan(template) |> result.map_error(ScannerError),
  )
  use ast <- result.map(parse(tokens) |> result.map_error(ParserError))
  fn(env: Value) -> Result(String, Error) {
    interpret(ast, env) |> result.map_error(InterpreterError)
  }
}

// parser

// Mustache syntactical grammar:
//
// template                 -> line* EOF;
// line                     -> expression* NEWLINE? ;
// expression               -> parent
// parent                   -> parent_opening line* closing_tag | block;
// parent_opening           -> LEFT_DELIMITER "<" name RIGHT_DELIMITER ;
// block                    -> block_opening line* closing_tag | inverted_section ;
// block_opening            -> LEFT_DELIMITER "$" name RIGHT_DELIMITER ;
// inverted_section         -> inverted_section_opening line* closing_tag | section;
// inverted_section_opening -> LEFT_DELIMITER "^" name RIGHT_DELIMITER ;
// section                  -> section_opening line* closing_tag | partial ;
// section_opening          -> LEFT_DELIMITER "#" name RIGHT_DELIMITER ;
// closing_tag              -> LEFT_DELIMITER "/" name RIGHT_DELIMITER ;
// partial                  -> LEFT_DELIMITER ">" name RIGHT_DELIMITER | raw_variable ;
// raw_variable             -> ("{{{" name "}}}") | (LEFT_DELIMITER "&" name RIGHT_DELIMITER) | variable ;
// variable                 -> LEFT_DELIMITER name RIGHT_DELIMITER | primary ;
// name                     -> "." | (IDENTIFIER? ("." IDENTIFIER)*)) ;
// primary                  -> TEXT | WHITESPACE

@internal
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

@internal
pub fn parse(
  tokens: List(scanner.Token),
) -> Result(List(Expression), SyntaxError) {
  parse_template(tokens)
}

// rules

fn parse_template(
  tokens: List(scanner.Token),
) -> Result(List(Expression), SyntaxError) {
  use #(lines, tail) <- result.try(parse_lines(tokens, []))
  use _ <- result.map(expect_token(tail, scanner.Eof))
  prune_lines(lines)
  |> list.flatten()
}

fn parse_lines(
  tokens: List(scanner.Token),
  acc: List(List(Expression)),
) -> Result(#(List(List(Expression)), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Eof] -> Ok(#(list.reverse(acc), tokens))
    non_empty -> {
      use #(line, tail) <- result.try(parse_line(non_empty))
      parse_lines(tail, list.prepend(acc, line))
    }
  }
}

fn parse_line(
  tokens: List(scanner.Token),
) -> Result(#(List(Expression), List(scanner.Token)), SyntaxError) {
  use #(expressions, tail) <- result.map(parse_expressions(tokens, []))
  case tail {
    [scanner.NewlineLiteral(nl), ..tail] ->
      expressions
      |> list.reverse()
      |> list.prepend(Newline(nl))
      |> list.reverse()
      |> pair.new(tail)
    _ -> #(expressions, tail)
  }
}

fn parse_expressions(
  tokens: List(scanner.Token),
  acc: List(Expression),
) -> Result(#(List(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.Eof]
    | [scanner.NewlineLiteral(_), ..]
    | [scanner.LeftDelimiter, scanner.ClosingIndicator, ..] ->
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
    [scanner.LeftDelimiter, scanner.ParentIndicator, ..] ->
      parse_enclosed(tokens, parse_parent_opening, Parent)
    _ -> parse_block(tokens)
  }
}

fn parse_parent_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.ParentIndicator)
}

fn parse_block(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.BlockIndicator, ..] ->
      parse_enclosed(tokens, parse_block_opening, Block)
    _ -> parse_inverted_section(tokens)
  }
}

fn parse_block_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.BlockIndicator)
}

fn parse_inverted_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.InvertedSectionIndicator, ..] ->
      parse_enclosed(tokens, parse_inverted_section_opening, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.InvertedSectionIndicator)
}

fn parse_section(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.SectionIndicator, ..] ->
      parse_enclosed(tokens, parse_section_opening, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_opening(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, scanner.SectionIndicator)
}

fn parse_closing_tag(
  tokens: List(scanner.Token),
) -> Result(#(List(String), List(scanner.Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    scanner.ClosingIndicator,
  ))
  #(path, tail)
}

fn parse_partial(
  tokens: List(scanner.Token),
) -> Result(#(Option(Expression), List(scanner.Token)), SyntaxError) {
  case tokens {
    [scanner.LeftDelimiter, scanner.PartialIndicator, ..] -> {
      use #(path, tail) <- result.map(parse_tag_with_indicator(
        tokens,
        scanner.PartialIndicator,
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
    [scanner.LeftDelimiter, scanner.RawVariableIndicator, ..] ->
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
    scanner.RawVariableIndicator,
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
    [
      scanner.WhitespaceLiteral(_),
      scanner.Ignored,
      scanner.NewlineLiteral(_),
      ..tail
    ] -> parse_primary(tail)
    [scanner.WhitespaceLiteral(_), scanner.Ignored, scanner.Eof] ->
      Ok(#(None, [scanner.Eof]))
    [scanner.Ignored, scanner.NewlineLiteral(_), ..tail]
    | [scanner.Ignored, ..tail]
    | [scanner.SetDelimiters(_, _), ..tail] -> parse_primary(tail)
    [scanner.TextLiteral(value), ..tail] -> Ok(emit_expr(Text, value, tail))
    [scanner.WhitespaceLiteral(value), ..tail] ->
      Ok(emit_expr(Whitespace, value, tail))
    [scanner.Eof] | [scanner.NewlineLiteral(_), ..] | [_, ..] ->
      Ok(#(None, tokens))
    [] -> Error(UnexpectedEndOfInputError)
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

fn prune_lines(lines: List(List(Expression))) -> List(List(Expression)) {
  list.map(lines, fn(line) {
    case line {
      line -> line
    }
  })
}

// interpreter

/// `RuntimeError` represents an error encountered during interpreting.
pub type RuntimeError {
  /// `UnknownExpressionError` is returned when the interpreter doesn't know
  /// how to evaluate a given expression.
  UnknownExpressionError
}

@internal
pub fn interpret(
  template: List(Expression),
  environment: Value,
) -> Result(String, RuntimeError) {
  use tree <- result.map(evaluate_exprs(
    template,
    Environment(environment, None),
    string_tree.new(),
  ))
  string_tree.to_string(tree)
}

fn evaluate_exprs(
  exprs: List(Expression),
  env: Environment,
  acc: StringTree,
) -> Result(StringTree, RuntimeError) {
  case exprs {
    [] -> Ok(acc)
    [expr, ..tail] -> {
      use value <- result.try(evaluate(expr, env))
      evaluate_exprs(tail, env, string_tree.append_tree(acc, value))
    }
  }
}

fn evaluate(
  expr: Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  case expr {
    Text(value) | Whitespace(value) | Newline(value) ->
      Ok(string_tree.from_string(value))
    Variable(_) -> evaluate_variable(expr, env)
    RawVariable(_) -> evaluate_raw_variable(expr, env)
    Section(_, _) -> evaluate_section(expr, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  expr: Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert Variable(path) = expr
  env
  |> get_and_format(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_raw_variable(
  expr: Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert RawVariable(path) = expr
  env
  |> get_and_format_raw(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_section(
  expr: Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert Section(path, content) = expr
  case get(env, path) {
    None | Some(Bool(False)) -> Ok(string_tree.new())
    Some(List(l)) ->
      list.map(l, fn(c) {
        evaluate_exprs(content, Environment(c, Some(env)), string_tree.new())
      })
      |> result.all()
      |> result.map(fn(trees) {
        list.fold(trees, string_tree.new(), string_tree.append_tree)
      })
    Some(context) ->
      evaluate_exprs(
        content,
        Environment(context, Some(env)),
        string_tree.new(),
      )
  }
}

// value

/// `Value` represents any of the possible types that can be passed as the
/// right-hand side of the dictionary used as input for Mustache templates
/// (what Mustache calls a "hash" in its official documentation).
pub type Value {
  Dict(Dict(String, Value))
  Int(Int)
  Float(Float)
  String(String)
  Bool(Bool)
  List(List(Value))
}

pub fn from_dict(value: Dict(String, Value)) -> Value {
  Dict(value)
}

pub fn from_int(value: Int) -> Value {
  Int(value)
}

pub fn from_float(value: Float) -> Value {
  Float(value)
}

pub fn from_string(value: String) -> Value {
  String(value)
}

pub fn from_bool(value: Bool) -> Value {
  Bool(value)
}

pub fn from_list(value: List(Value)) -> Value {
  List(value)
}

// environment

@internal
pub type Environment {
  Environment(value: Value, parent: Option(Environment))
}

@internal
pub fn get_and_format(env: Environment, path: List(String)) -> String {
  get_and_format_raw(env, path) |> houdini.escape()
}

@internal
pub fn get_and_format_raw(env: Environment, path: List(String)) -> String {
  get(env, path) |> format()
}

@internal
pub fn get(env: Environment, path: List(String)) -> Option(Value) {
  case find_path_root_in_stack(env, path) {
    Some(#(val, [])) -> Some(val)
    Some(#(val, tail)) -> get_with_path(val, tail)
    None -> None
  }
}

fn find_path_root_in_stack(
  env: Environment,
  path: List(String),
) -> Option(#(Value, List(String))) {
  case path {
    [head, ..tail] ->
      case get_in_val(env.value, head) {
        Some(found) -> Some(#(found, tail))
        None ->
          case env.parent {
            Some(parent) -> find_path_root_in_stack(parent, path)
            None -> None
          }
      }
    [] -> None
  }
}

@internal
pub fn get_with_path(val: Value, path: List(String)) -> Option(Value) {
  case path {
    [] -> None
    [key] -> get_in_val(val, key)
    [key, ..tail] -> {
      use val <- option.then(get_in_val(val, key))
      get_with_path(val, tail)
    }
  }
}

fn get_in_val(val: Value, key: String) -> Option(Value) {
  case key {
    "." -> Some(val)
    any ->
      case val {
        Dict(dictionary) -> dict.get(dictionary, any) |> option.from_result()
        _ -> None
      }
  }
}

fn format(val: Option(Value)) -> String {
  case val {
    Some(some) ->
      case some {
        Int(value) -> int.to_string(value)
        Float(value) -> float.to_string(value)
        String(value) -> value
        Bool(value) -> bool.to_string(value)
        _ -> ""
      }
    None -> ""
  }
}
