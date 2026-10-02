import gleam/dict.{type Dict}
import gleam/option.{None}
import gleam/result
import gleam/string_tree.{type StringTree}

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner
import pomade/internal/value

/// `Template` represents a compiled template. Since this is a type alias to a
/// function, simply pass it a dictionary of input values.
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
) -> Result(String, Error) {
  use template <- result.try(compile(template))
  apply(template, data, partials)
}

pub fn render_tree(
  template: String,
  data: Value,
  partials: Dict(String, String),
) -> Result(StringTree, Error) {
  use template <- result.try(compile(template))
  apply_tree(template, data, partials)
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
) -> Result(String, Error) {
  let Template(template) = template
  template(data, partials)
  |> result.map(string_tree.to_string)
  |> result.map_error(error_from_runtime_error)
}

pub fn apply_tree(
  template: Template,
  data: Value,
  partials: Dict(String, String),
) -> Result(StringTree, Error) {
  let Template(template) = template
  template(data, partials)
  |> result.map_error(error_from_runtime_error)
}

// errors

pub type Error {
  CompilationError(String)
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

pub type Value =
  value.Value

pub fn dict(value: Dict(String, Value)) -> Value {
  value.Dict(value)
}

pub fn int(value: Int) -> Value {
  value.Int(value)
}

pub fn float(value: Float) -> Value {
  value.Float(value)
}

pub fn string(value: String) -> Value {
  value.String(value)
}

pub fn bool(value: Bool) -> Value {
  value.Bool(value)
}

pub fn list(value: List(Value)) -> Value {
  value.List(value)
}
