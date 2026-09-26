import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string_tree.{type StringTree}

import pomade/value

import pomade/internal/environment.{type Environment, Environment}
import pomade/internal/parser

/// `RuntimeError` represents an error encountered during interpreting.
pub type RuntimeError {
  /// `UnknownExpressionError` is returned when the interpreter doesn't know
  /// how to evaluate a given expression.
  UnknownExpressionError
}

pub fn interpret(
  template: List(parser.Expression),
  environment: value.Value,
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
    parser.InvertedSection(_, _) -> evaluate_inverted_section(expr, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Variable(path) = expr
  env
  |> environment.get_and_format(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_raw_variable(
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.RawVariable(path) = expr
  env
  |> environment.get_and_format_raw(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_section(
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Section(path, content) = expr
  case environment.get(env, path) {
    None | Some(value.Bool(False)) -> Ok(string_tree.new())
    Some(value.List(l)) ->
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

fn evaluate_inverted_section(
  expr: parser.Expression,
  env: Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.InvertedSection(path, content) = expr
  case environment.get(env, path) {
    None | Some(value.Bool(False)) | Some(value.List([])) ->
      evaluate_exprs(content, env, string_tree.new())
    _ -> Ok(string_tree.new())
  }
}
