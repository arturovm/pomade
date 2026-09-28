import gleam/dict.{type Dict}
import gleam/option.{type Option, None}
import gleam/result

import pomade/value

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner

/// `Template` represents a compiled template. Since this is a type alias to a
/// function, simply pass it a dictionary of input values.
pub type Template =
  fn(value.Value, Option(Dict(String, String))) -> Result(String, Error)

/// `Error` aggregates all the possible error types that can be emitted by the
/// different rendering phases.
pub type Error {
  Error(message: String)
}

/// `render` renders a template source string directly. Useful when convenience
/// is the priority.
pub fn render(
  template: String,
  environment: value.Value,
  partials: Option(Dict(String, String)),
) -> Result(String, Error) {
  use template <- result.try(compile(template))
  template(environment, partials)
}

/// `compile` prepares a template for future application, to avoid the overhead
/// of scanning and parsing a template from scratch every time. Prefer this
/// when speed is important.
pub fn compile(template: String) -> Result(Template, Error) {
  use tokens <- result.try(
    scanner.scan(template) |> result.map_error(map_lexical_error),
  )
  let rewritten = rewriter.rewrite(tokens, None)
  use ast <- result.map(
    parser.parse(rewritten) |> result.map_error(map_syntax_error),
  )
  fn(env: value.Value, partials: Option(Dict(String, String))) -> Result(
    String,
    Error,
  ) {
    interpreter.interpret(ast, env, partials)
    |> result.map_error(map_runtime_error)
  }
}

// errors

fn map_lexical_error(error: scanner.LexicalError) -> Error {
  Error(message: "lexical error: " <> scanner.error_to_string(error))
}

fn map_syntax_error(error: parser.SyntaxError) -> Error {
  Error(message: "syntax error: " <> parser.error_to_string(error))
}

fn map_runtime_error(error: interpreter.RuntimeError) -> Error {
  Error(message: "runtime error: " <> interpreter.error_to_string(error))
}

pub fn error_to_string(error: Error) -> String {
  error.message
}
