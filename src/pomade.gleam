import gleam/dict.{type Dict}
import gleam/option.{type Option, None}
import gleam/result

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner
import pomade/internal/value

/// `Template` represents a compiled template. Since this is a type alias to a
/// function, simply pass it a dictionary of input values.
pub opaque type Template {
  Template(
    fn(value.Value, Option(Dict(String, String))) -> Result(String, String),
  )
}

/// `render` renders a template source string directly. Useful when convenience
/// is the priority.
pub fn render(
  template: String,
  data: Value,
  partials: Option(Dict(String, String)),
) -> Result(String, String) {
  use template <- result.try(compile(template))
  apply(template, data, partials)
}

/// `compile` prepares a template for future application, to avoid the overhead
/// of scanning and parsing a template from scratch every time. Prefer this
/// when speed is important.
pub fn compile(template: String) -> Result(Template, String) {
  use tokens <- result.try(
    scanner.scan(template) |> result.map_error(lexical_error_to_string),
  )
  let rewritten = rewriter.rewrite(tokens, None)
  use ast <- result.map(
    parser.parse(rewritten) |> result.map_error(syntax_error_to_string),
  )
  Template(fn(data: Value, partials: Option(Dict(String, String))) -> Result(
    String,
    String,
  ) {
    interpreter.interpret(ast, data, partials)
    |> result.map_error(runtime_error_to_string)
  })
}

/// `apply` takes a pre-compiled template and applies it to the supplied data
/// and partials.
pub fn apply(
  template: Template,
  data: Value,
  partials: Option(Dict(String, String)),
) -> Result(String, String) {
  let Template(template) = template
  template(data, partials)
}

// errors

fn lexical_error_to_string(error: scanner.LexicalError) -> String {
  "lexical error: " <> scanner.error_to_string(error)
}

fn syntax_error_to_string(error: parser.SyntaxError) -> String {
  "syntax error: " <> parser.error_to_string(error)
}

fn runtime_error_to_string(error: interpreter.RuntimeError) -> String {
  "runtime error: " <> interpreter.error_to_string(error)
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
