import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string_tree.{type StringTree}
import pomade/internal/filter
import pomade/internal/scanner

import pomade/value

import pomade/internal/environment
import pomade/internal/parser

/// `RuntimeError` represents an error encountered during interpreting.
pub type RuntimeError {
  /// `UnknownExpressionError` is returned when the interpreter doesn't know
  /// how to evaluate a given expression.
  UnknownExpressionError
  /// `PartialError` is used to report that an error occurred during partial
  /// evaluation.
  PartialError(String)
  /// `PartialError` is used to report that an error occurred during partial
  /// evaluation.
  PartialNotFoundError
}

pub fn interpret(
  template: List(parser.Expression),
  environment: value.Value,
  partials: Option(Dict(String, String)),
) -> Result(String, RuntimeError) {
  use tree <- result.map(evaluate_exprs(
    template,
    environment.Environment(environment, partials, None),
    string_tree.new(),
  ))
  string_tree.to_string(tree)
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  env: environment.Environment,
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
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  case expr {
    parser.Text(value) | parser.Whitespace(value) | parser.Newline(value) ->
      Ok(string_tree.from_string(value))
    parser.Variable(_) -> evaluate_variable(expr, env)
    parser.RawVariable(_) -> evaluate_raw_variable(expr, env)
    parser.Section(_, _) -> evaluate_section(expr, env)
    parser.InvertedSection(_, _) -> evaluate_inverted_section(expr, env)
    parser.Partial(_) -> evaluate_partial(expr, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Variable(path) = expr
  env
  |> environment.get_and_format(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_raw_variable(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.RawVariable(path) = expr
  env
  |> environment.get_and_format_raw(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_section(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Section(path, content) = expr
  case environment.get(env, path) {
    None | Some(value.Bool(False)) -> Ok(string_tree.new())
    Some(value.List(l)) ->
      list.map(l, fn(c) {
        evaluate_exprs(
          content,
          environment.Environment(..env, value: c, parent: Some(env)),
          string_tree.new(),
        )
      })
      |> result.all()
      |> result.map(fn(trees) {
        list.fold(trees, string_tree.new(), string_tree.append_tree)
      })
    Some(context) ->
      evaluate_exprs(
        content,
        environment.Environment(..env, value: context, parent: Some(env)),
        string_tree.new(),
      )
  }
}

fn evaluate_inverted_section(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.InvertedSection(path, content) = expr
  case environment.get(env, path) {
    None | Some(value.Bool(False)) | Some(value.List([])) ->
      evaluate_exprs(content, env, string_tree.new())
    _ -> Ok(string_tree.new())
  }
}

fn evaluate_partial(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Partial(path) = expr
  case environment.get_partial(env, path) {
    Some(source) -> {
      use tokens <- result.try(
        scanner.scan(source) |> result.map_error(fn(_) { PartialError("") }),
      )
      let filtered = filter.filter(tokens)
      use ast <- result.try(
        parser.parse(filtered)
        |> result.map_error(fn(_) { PartialError("") }),
      )
      use res <- result.map(evaluate_exprs(ast, env, string_tree.new()))
      res
    }
    None -> Error(PartialNotFoundError)
  }
}
