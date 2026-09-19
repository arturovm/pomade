import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/result
import gleam/string_tree.{type StringTree}

import pomade/internal/parser

pub type RuntimeError {
  UnknownExpressionError
}

pub fn interpret(
  template: parser.Template,
  environment: dict.Dict(String, dynamic.Dynamic),
) -> Result(String, RuntimeError) {
  let parser.Template(exprs) = template
  use trees <- result.map(evaluate_exprs(exprs, environment, []))
  trees
  |> list.fold(string_tree.new(), string_tree.append_tree)
  |> string_tree.to_string()
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  env: dict.Dict(String, dynamic.Dynamic),
  acc: List(StringTree),
) -> Result(List(StringTree), RuntimeError) {
  case exprs {
    [] -> Ok(list.reverse(acc))
    [expr, ..tail] -> {
      use value <- result.try(evaluate(expr, env))
      evaluate_exprs(tail, env, list.prepend(acc, value))
    }
  }
}

fn evaluate(
  expr: parser.Expression,
  _env: dict.Dict(String, dynamic.Dynamic),
) -> Result(StringTree, RuntimeError) {
  case expr {
    parser.Text(value) | parser.Newline(value) ->
      Ok(string_tree.from_string(value))
    _ -> Error(UnknownExpressionError)
  }
}
