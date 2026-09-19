import gleam/dict.{type Dict}
import gleam/result
import pomade/internal/interpreter
import pomade/internal/parser

import pomade/internal/scanner

import pomade/value.{type Value}

pub type Template =
  fn(Dict(String, Value)) -> Result(String, interpreter.RuntimeError)

pub type PomadeError {
  PomadeError
}

pub fn render(template: String, environment: Dict(String, Value)) -> String {
  case scanner.scan(template) {
    Error(_) -> ""
    Ok(tokens) ->
      case parser.parse(tokens) {
        Error(_) -> ""
        Ok(ast) ->
          case interpreter.interpret(ast, environment) {
            Error(_) -> ""
            Ok(result) -> result
          }
      }
  }
}

pub fn compile(template: String) -> Result(Template, PomadeError) {
  use tokens <- result.try(
    scanner.scan(template) |> result.map_error(fn(_) { PomadeError }),
  )
  use ast <- result.map(
    parser.parse(tokens) |> result.map_error(fn(_) { PomadeError }),
  )
  interpreter.interpret(ast, _)
}
