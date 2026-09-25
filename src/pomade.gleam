import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string_tree.{type StringTree}
import houdini

import pomade/internal/filter
import pomade/internal/parser
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
  ParserError(parser.SyntaxError)
  /// `InterpreterError` reports a runtime error, encountered during interpreting.
  InterpreterError(RuntimeError)
}

/// `render` renders a template source string directly. Useful when convenience
/// is the priority.
pub fn render(template: String, environment: Value) -> Result(String, Error) {
  use template <- result.try(compile(template))
  template(environment)
}

/// `compile` prepares a template for future application, to avoid the overhead
/// of scanning and parsing a template from scratch every time. Prefer this
/// when speed is important.
pub fn compile(template: String) -> Result(Template, Error) {
  use tokens <- result.try(
    scanner.scan(template)
    |> result.map_error(ScannerError)
    |> result.map(filter.filter),
  )
  use ast <- result.map(parser.parse(tokens) |> result.map_error(ParserError))
  fn(env: Value) -> Result(String, Error) {
    interpret(ast, env) |> result.map_error(InterpreterError)
  }
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
  template: List(parser.Expression),
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
  exprs: List(parser.Expression),
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
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  case expr {
    parser.Text(value) | parser.Whitespace(value) | parser.Newline(value) ->
      Ok(string_tree.from_string(value))
    parser.Variable(_) -> evaluate_variable(expr, env)
    parser.RawVariable(_) -> evaluate_raw_variable(expr, env)
    parser.Section(_, _) -> evaluate_section(expr, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Variable(path) = expr
  env
  |> get_and_format(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_raw_variable(
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.RawVariable(path) = expr
  env
  |> get_and_format_raw(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_section(
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Section(path, content) = expr
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
