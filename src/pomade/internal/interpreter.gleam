import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import pomade/internal/environment
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner
import pomade/internal/value

/// `RuntimeError` represents an error encountered during interpreting.
pub type RuntimeError {
  /// `UnknownExpressionError` is returned when the interpreter doesn't know
  /// how to evaluate a given expression.
  UnknownExpressionError
  /// `PartialError` is used to report that an error occurred during partial
  /// evaluation.
  PartialError(name: String, error: PartialError)
}

pub opaque type PartialError {
  LexicalError(scanner.LexicalError)
  SyntaxError(parser.SyntaxError)
  RuntimeError(RuntimeError)
}

pub fn interpret(
  template: List(parser.Expression),
  environment: value.Value,
  partials: Dict(String, String),
) -> Result(String, RuntimeError) {
  evaluate_exprs(
    template,
    environment.Environment(environment, partials, None),
    "",
  )
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  env: environment.Environment,
  acc: String,
) -> Result(String, RuntimeError) {
  case exprs {
    [] -> Ok(acc)
    [parser.Literal(rewriter.Literal(_, value)), ..tail] ->
      evaluate_exprs(tail, env, acc <> value)
    [parser.Variable(rewriter.Variable(_, path)), ..tail] ->
      evaluate_exprs(tail, env, acc <> evaluate_variable(path, env))
    [parser.RawVariable(rewriter.RawVariable(_, path)), ..tail] ->
      evaluate_exprs(tail, env, acc <> evaluate_raw_variable(path, env))
    [expr, ..tail] ->
      case evaluate_with_nested(expr, env) {
        Ok(value) -> evaluate_exprs(tail, env, acc <> value)
        error -> error
      }
  }
}

fn evaluate_with_nested(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(String, RuntimeError) {
  case expr {
    parser.Section(rewriter.SectionStart(_, path), content) ->
      evaluate_section(path, content, env)
    parser.InvertedSection(rewriter.InvertedSectionStart(_, path), content) ->
      evaluate_inverted_section(path, content, env)
    parser.Partial(rewriter.Partial(_, name), indentation) ->
      evaluate_partial(name, indentation, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  path: List(String),
  env: environment.Environment,
) -> String {
  environment.get_and_format(env, path)
}

fn evaluate_raw_variable(
  path: List(String),
  env: environment.Environment,
) -> String {
  environment.get_and_format_raw(env, path)
}

fn evaluate_section(
  path: List(String),
  content: List(parser.Expression),
  env: environment.Environment,
) -> Result(String, RuntimeError) {
  case environment.get(env, path) {
    Error(Nil) | Ok(value.Bool(False)) -> Ok("")
    Ok(value.List(l)) ->
      list.map(l, fn(c) {
        evaluate_exprs(
          content,
          environment.Environment(..env, value: c, parent: Some(env)),
          "",
        )
      })
      |> result.all()
      |> result.map(fn(trees) {
        list.fold(trees, "", fn(acc, val) { acc <> val })
      })
    Ok(context) ->
      evaluate_exprs(
        content,
        environment.Environment(..env, value: context, parent: Some(env)),
        "",
      )
  }
}

fn evaluate_inverted_section(
  path: List(String),
  content: List(parser.Expression),
  env: environment.Environment,
) -> Result(String, RuntimeError) {
  case environment.get(env, path) {
    Error(Nil) | Ok(value.Bool(False)) | Ok(value.List([])) ->
      evaluate_exprs(content, env, "")
    _ -> Ok("")
  }
}

fn evaluate_partial(
  name: String,
  indentation: Option(String),
  env: environment.Environment,
) -> Result(String, RuntimeError) {
  case environment.get_partial(env, name) {
    Ok(source) -> {
      use tokens <- result.try(
        scanner.scan(source)
        |> result.map_error(fn(e) { PartialError(name, LexicalError(e)) }),
      )
      let rewritten = rewriter.rewrite(tokens, indentation)
      use ast <- result.try(
        parser.parse(rewritten)
        |> result.map_error(fn(e) { PartialError(name, SyntaxError(e)) }),
      )
      use partial_result <- result.map(
        evaluate_exprs(ast, env, "")
        |> result.map_error(fn(e) { PartialError(name, RuntimeError(e)) }),
      )
      partial_result
    }
    Error(_) -> Ok("")
  }
}

// formatting

pub fn error_to_string(error: RuntimeError) -> String {
  case error {
    UnknownExpressionError -> "unknown expression"
    PartialError(name, error) ->
      "error found while rendering partial '"
      <> name
      <> "': "
      <> partial_error_to_string(error)
  }
}

fn partial_error_to_string(error: PartialError) -> String {
  case error {
    LexicalError(error) -> scanner.error_to_string(error)
    SyntaxError(error) -> parser.error_to_string(error)
    RuntimeError(error) -> error_to_string(error)
  }
}
