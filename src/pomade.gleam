import gleam/dict.{type Dict}
import gleam/option.{None}
import gleam/result
import gleam/string_tree.{type StringTree}

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner
import pomade/internal/value

/// `Template` represents a compiled template.
pub opaque type Template {
  Template(
    fn(value.Value, Dict(String, String)) ->
      Result(StringTree, interpreter.RuntimeError),
  )
}

/// `render` renders a template source string directly. Useful when convenience
/// is the priority.
pub fn render(
  template: String,
  data: Value,
  partials: Dict(String, String),
) -> Result(StringTree, Error) {
  use template <- result.try(compile(template))
  apply(template, data, partials)
}

/// `render_string` is like `render`, but it returns a `String` instead of a
/// `StringTree`. Internally, `render_string` calls `render`, and then converts
/// the result, so some allocations are implied. Because of this, prefer
/// `render` whenever possible, if your target API permits it.
pub fn render_string(
  template: String,
  data: Value,
  partials: Dict(String, String),
) -> Result(String, Error) {
  render(template, data, partials)
  |> result.map(string_tree.to_string)
}

/// `compile` prepares a template for future application, to avoid the overhead
/// of scanning and parsing a template from scratch every time. Prefer this
/// when speed is important.
pub fn compile(template: String) -> Result(Template, Error) {
  use tokens <- result.try(
    scanner.scan(template) |> result.map_error(error_from_lexical_error),
  )
  let rewritten = rewriter.rewrite(tokens, None)
  use ast <- result.map(
    parser.parse(rewritten) |> result.map_error(error_from_syntax_error),
  )
  Template(fn(data, partials) { interpreter.interpret(ast, data, partials) })
}

/// `apply` takes a pre-compiled template and applies it to the supplied data
/// and partials.
pub fn apply(
  template: Template,
  data: Value,
  partials: Dict(String, String),
) -> Result(StringTree, Error) {
  let Template(template) = template
  template(data, partials)
  |> result.map_error(error_from_runtime_error)
}

/// `apply_string` is like `apply`, but it returns a `String` instead of a
/// `StringTree`. Internally, `apply_string` calls `apply`, and then converts
/// the result, so some allocations are implied. Because of this, prefer
/// `apply` whenever possible, if your target API permits it.
pub fn apply_string(
  template: Template,
  data: Value,
  partials: Dict(String, String),
) -> Result(String, Error) {
  apply(template, data, partials)
  |> result.map(string_tree.to_string)
}

// errors

/// Error is used to report an error from the API.
pub type Error {
  /// `CompilationError` represents an error encountered either during scanning
  /// or during parsing.
  CompilationError(String)
  /// `RuntimeError` represents an error encountered during interpretation.
  RuntimeError(String)
}

fn error_from_lexical_error(error: scanner.LexicalError) -> Error {
  CompilationError("lexical error: " <> scanner.error_to_string(error))
}

fn error_from_syntax_error(error: parser.SyntaxError) -> Error {
  CompilationError("syntax error: " <> parser.error_to_string(error))
}

fn error_from_runtime_error(error: interpreter.RuntimeError) -> Error {
  RuntimeError("runtime error: " <> interpreter.error_to_string(error))
}

// value

/// `Value` is used to represent the input types that a Mustache template
/// accepts. It also allows the API to accept heterogeneous dictionaries, which
/// Gleam, understandably, does not support natively.
pub type Value =
  value.Value

/// `dict` creates a `Value` from a `Dict(String, Value)`.
pub fn dict(value: Dict(String, Value)) -> Value {
  value.Dict(value)
}

/// `int` creates a `Value` from an `Int`.
pub fn int(value: Int) -> Value {
  value.Int(value)
}

/// `float` creates a `Value` from a `Float`.
pub fn float(value: Float) -> Value {
  value.Float(value)
}

/// `string` creates a `Value` from a `String`.
pub fn string(value: String) -> Value {
  value.String(value)
}

/// `bool` creates a `Value` from a `Bool`.
pub fn bool(value: Bool) -> Value {
  value.Bool(value)
}

/// `list` creates a `Value` from a `List(Value)`.
pub fn list(value: List(Value)) -> Value {
  value.List(value)
}
