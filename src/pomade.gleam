import gleam/dict.{type Dict}
import gleam/option.{type Option}
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
  /// `ScannerError` reports a lexical error, encountered during scanning.
  ScannerError(scanner.LexicalError)
  /// `ParserError` reports a syntax error, encountered during parsing.
  ParserError(parser.SyntaxError)
  /// `InterpreterError` reports a runtime error, encountered during interpreting.
  InterpreterError(interpreter.RuntimeError)
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
    scanner.scan(template) |> result.map_error(ScannerError),
  )
  let rewritten = rewriter.rewrite(tokens)
  use ast <- result.map(
    parser.parse(rewritten) |> result.map_error(ParserError),
  )
  fn(env: value.Value, partials: Option(Dict(String, String))) -> Result(
    String,
    Error,
  ) {
    interpreter.interpret(ast, env, partials)
    |> result.map_error(InterpreterError)
  }
}
