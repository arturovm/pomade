import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string_tree.{type StringTree}

import pomade/internal/environment
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner

import pomade/value

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
  partials: Option(Dict(String, String)),
) -> Result(String, RuntimeError) {
  use tree <- result.map(evaluate_exprs(
    template,
    environment.Environment(environment, partials, None),
    string_tree.new(),
  ))
  string_tree.to_string(tree)
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  env: environment.Environment,
  acc: StringTree,
) -> Result(StringTree, RuntimeError) {
  case exprs {
    [] -> Ok(acc)
    [expr, ..tail] -> {
      use value <- result.try(evaluate(expr, env))
      evaluate_exprs(tail, env, string_tree.append_tree(acc, value))
    }
  }
}

fn evaluate(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  case expr {
    parser.Text(scanner.Text(_, value))
    | parser.Whitespace(scanner.Whitespace(_, value))
    | parser.Newline(scanner.Newline(_, value)) ->
      Ok(string_tree.from_string(value))
    parser.Variable(_) -> evaluate_variable(expr, env)
    parser.RawVariable(_) -> evaluate_raw_variable(expr, env)
    parser.Section(_, _) -> evaluate_section(expr, env)
    parser.InvertedSection(_, _) -> evaluate_inverted_section(expr, env)
    parser.Partial(_) -> evaluate_partial(expr, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Variable(scanner.Variable(_, path)) = expr
  env
  |> environment.get_and_format(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_raw_variable(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.RawVariable(scanner.RawVariable(_, path)) = expr
  env
  |> environment.get_and_format_raw(path)
  |> string_tree.from_string()
  |> Ok()
}

fn evaluate_section(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Section(scanner.SectionStart(_, path), content) = expr
  case environment.get(env, path) {
    None | Some(value.Bool(False)) -> Ok(string_tree.new())
    Some(value.List(l)) ->
      list.map(l, fn(c) {
        evaluate_exprs(
          content,
          environment.Environment(..env, value: c, parent: Some(env)),
          string_tree.new(),
        )
      })
      |> result.all()
      |> result.map(fn(trees) {
        list.fold(trees, string_tree.new(), string_tree.append_tree)
      })
    Some(context) ->
      evaluate_exprs(
        content,
        environment.Environment(..env, value: context, parent: Some(env)),
        string_tree.new(),
      )
  }
}

fn evaluate_inverted_section(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.InvertedSection(
    scanner.InvertedSectionStart(_, path),
    content,
  ) = expr
  case environment.get(env, path) {
    None | Some(value.Bool(False)) | Some(value.List([])) ->
      evaluate_exprs(content, env, string_tree.new())
    _ -> Ok(string_tree.new())
  }
}

fn evaluate_partial(
  expr: parser.Expression,
  env: environment.Environment,
) -> Result(StringTree, RuntimeError) {
  let assert parser.Partial(scanner.Partial(_, name)) = expr
  case environment.get_partial(env, name) {
    Some(source) -> {
      use tokens <- result.try(
        scanner.scan(source)
        |> result.map_error(fn(e) { PartialError(name, LexicalError(e)) }),
      )
      let rewritten = rewriter.rewrite(tokens)
      use ast <- result.try(
        parser.parse(rewritten)
        |> result.map_error(fn(e) { PartialError(name, SyntaxError(e)) }),
      )
      use partial_result <- result.map(
        evaluate_exprs(ast, env, string_tree.new())
        |> result.map_error(fn(e) { PartialError(name, RuntimeError(e)) }),
      )
      partial_result
    }
    None -> Ok(string_tree.new())
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
