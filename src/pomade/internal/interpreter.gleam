import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string_tree.{type StringTree}

import pomade/internal/environment.{type Value}
import pomade/internal/parser

pub type RuntimeError {
  UnknownExpressionError
}

pub fn interpret(
  template: parser.Template,
  environment: Dict(String, Value),
) -> Result(String, RuntimeError) {
  let parser.Template(exprs) = template
  use trees <- result.map(evaluate_exprs(exprs, environment, []))
  trees
  |> list.fold(string_tree.new(), string_tree.append_tree)
  |> string_tree.to_string()
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  env: Dict(String, Value),
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
  env: Dict(String, Value),
) -> Result(StringTree, RuntimeError) {
  case expr {
    parser.Text(value) | parser.Newline(value) ->
      Ok(string_tree.from_string(value))
    parser.Variable(_) -> evaluate_variable(expr, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  expr: parser.Expression,
  env: Dict(String, Value),
) -> Result(StringTree, RuntimeError) {
  let assert parser.Variable(path) = expr
  environment.Dict(env)
  |> environment.get(path)
  |> string_tree.from_string()
  |> Ok()
}
