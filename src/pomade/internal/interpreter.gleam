import gleam/dict
import gleam/dynamic
import gleam/result

import pomade/internal/parser

pub type RuntimeError {
  UnknownExpressionError
}

pub fn interpret(
  template: parser.Template,
  environment: dict.Dict(String, dynamic.Dynamic),
) -> Result(String, RuntimeError) {
  let parser.Template(exprs) = template
  evaluate_exprs(exprs, environment, "")
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  env: dict.Dict(String, dynamic.Dynamic),
  acc: String,
) -> Result(String, RuntimeError) {
  case exprs {
    [] -> Ok(acc)
    [expr, ..tail] -> {
      use value <- result.try(evaluate(expr, env))
      evaluate_exprs(tail, env, acc <> value)
    }
  }
}

fn evaluate(
  expr: parser.Expression,
  _env: dict.Dict(String, dynamic.Dynamic),
) -> Result(String, RuntimeError) {
  case expr {
    parser.Text(value) | parser.Newline(value) -> Ok(value)
    _ -> Error(UnknownExpressionError)
  }
}
