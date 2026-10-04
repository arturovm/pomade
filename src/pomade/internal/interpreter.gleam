import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string_tree.{type StringTree}

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

type PartialCache =
  Dict(#(String, Option(String)), List(parser.Expression))

pub fn interpret(
  template: List(parser.Expression),
  environment: value.Value,
  partials: Dict(String, String),
) -> Result(StringTree, RuntimeError) {
  case
    evaluate_exprs(
      template,
      dict.new(),
      environment.Environment(environment, partials, None),
      string_tree.new(),
    )
  {
    Ok(#(value, _)) -> Ok(value)
    Error(error) -> Error(error)
  }
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  cache: PartialCache,
  env: environment.Environment,
  acc: StringTree,
) -> Result(#(StringTree, PartialCache), RuntimeError) {
  case exprs {
    [] -> Ok(#(acc, cache))
    [parser.Literal(rewriter.Literal(_, value)), ..tail] ->
      evaluate_exprs(tail, cache, env, string_tree.append(acc, value))
    [parser.Variable(rewriter.Variable(_, path)), ..tail] ->
      evaluate_exprs(
        tail,
        cache,
        env,
        string_tree.append(acc, evaluate_variable(path, env)),
      )
    [parser.RawVariable(rewriter.RawVariable(_, path)), ..tail] ->
      evaluate_exprs(
        tail,
        cache,
        env,
        string_tree.append(acc, evaluate_raw_variable(path, env)),
      )
    [expr, ..tail] ->
      case evaluate_with_nested(expr, cache, env, acc) {
        Ok(#(value, cache)) -> evaluate_exprs(tail, cache, env, value)
        Error(error) -> Error(error)
      }
  }
}

fn evaluate_with_nested(
  expr: parser.Expression,
  cache: PartialCache,
  env: environment.Environment,
  acc: StringTree,
) -> Result(#(StringTree, PartialCache), RuntimeError) {
  case expr {
    parser.Section(rewriter.SectionStart(_, path), content) ->
      evaluate_section(path, content, cache, env, acc)
    parser.InvertedSection(rewriter.InvertedSectionStart(_, path), content) ->
      evaluate_inverted_section(path, content, cache, env, acc)
    parser.Partial(rewriter.Partial(_, name), indentation) ->
      evaluate_partial(name, indentation, cache, env, acc)
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
  cache: PartialCache,
  env: environment.Environment,
  acc: StringTree,
) -> Result(#(StringTree, PartialCache), RuntimeError) {
  case environment.get(env, path) {
    Error(Nil) | Ok(value.Bool(False)) -> Ok(#(acc, cache))
    Ok(value.List(l)) ->
      list.try_fold(l, #(acc, cache), fn(acc, c) {
        evaluate_exprs(
          content,
          acc.1,
          environment.Environment(..env, value: c, parent: Some(env)),
          acc.0,
        )
      })
    Ok(context) ->
      evaluate_exprs(
        content,
        cache,
        environment.Environment(..env, value: context, parent: Some(env)),
        acc,
      )
  }
}

fn evaluate_inverted_section(
  path: List(String),
  content: List(parser.Expression),
  cache: PartialCache,
  env: environment.Environment,
  acc: StringTree,
) -> Result(#(StringTree, PartialCache), RuntimeError) {
  case environment.get(env, path) {
    Error(Nil) | Ok(value.Bool(False)) | Ok(value.List([])) ->
      evaluate_exprs(content, cache, env, acc)
    _ -> Ok(#(acc, cache))
  }
}

fn evaluate_partial(
  name: String,
  indentation: Option(String),
  cache: PartialCache,
  env: environment.Environment,
  acc: StringTree,
) -> Result(#(StringTree, PartialCache), RuntimeError) {
  case get_partial(name, indentation, env, cache) {
    Ok(#(ast, cache)) -> evaluate_exprs(ast, cache, env, acc)
    Error(error) -> Error(PartialError(name, error))
  }
}

fn get_partial(
  name: String,
  indentation: Option(String),
  env: environment.Environment,
  cache: PartialCache,
) -> Result(#(List(parser.Expression), PartialCache), PartialError) {
  case dict.get(cache, #(name, indentation)) {
    Ok(ast) -> Ok(#(ast, cache))
    Error(_) ->
      case environment.get_partial(env, name) {
        Ok(source) ->
          case compile_partial(source, indentation) {
            Ok(ast) -> Ok(#(ast, dict.insert(cache, #(name, indentation), ast)))
            Error(error) -> Error(error)
          }
        Error(_) -> Ok(#([], cache))
      }
  }
}

fn compile_partial(
  source: String,
  indentation: Option(String),
) -> Result(List(parser.Expression), PartialError) {
  use tokens <- result.try(
    scanner.scan(source)
    |> result.map_error(fn(e) { LexicalError(e) }),
  )
  let rewritten = rewriter.rewrite(tokens, indentation)
  use ast <- result.map(
    parser.parse(rewritten)
    |> result.map_error(fn(e) { SyntaxError(e) }),
  )
  ast
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
