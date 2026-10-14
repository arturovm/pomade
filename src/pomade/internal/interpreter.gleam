import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string_tree.{type StringTree}

import pomade/internal/environment
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner
import pomade/internal/value

pub fn interpret(
  template: List(parser.Expression),
  environment: value.Value,
  partials: Dict(String, List(parser.Expression)),
) -> StringTree {
  evaluate_exprs(
    template,
    environment.Environment(environment, partials, None, None),
    string_tree.new(),
  )
}

fn evaluate_exprs(
  exprs: List(parser.Expression),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  case exprs {
    [] -> acc
    [parser.Literal(rewriter.Literal(_, value)), ..tail] ->
      evaluate_exprs(tail, env, string_tree.append(acc, value))
    [parser.Indent, ..tail] ->
      evaluate_exprs(tail, env, case env.indentation {
        None -> acc
        Some(indentation) -> string_tree.append(acc, indentation)
      })
    [parser.Variable(rewriter.Variable(_, path)), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        string_tree.append(acc, evaluate_variable(path, env)),
      )
    [parser.RawVariable(rewriter.RawVariable(_, path)), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        string_tree.append(acc, evaluate_raw_variable(path, env)),
      )
    [parser.Section(rewriter.SectionStart(_, path), content), ..tail] ->
      evaluate_exprs(tail, env, evaluate_section(path, content, env, acc))
    [
      parser.InvertedSection(rewriter.InvertedSectionStart(_, path), content),
      ..tail
    ] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_inverted_section(path, content, env, acc),
      )
    [parser.Partial(rewriter.Partial(_, name), indentation), ..tail] ->
      evaluate_exprs(tail, env, evaluate_partial(name, indentation, env, acc))
    _ -> acc
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
  acc: StringTree,
) -> StringTree {
  case environment.get(env, path) {
    Error(Nil) | Ok(value.Bool(False)) -> acc
    Ok(value.List(l)) ->
      list.fold(l, acc, fn(acc, c) {
        evaluate_exprs(
          content,
          environment.Environment(..env, value: c, parent: Some(env)),
          acc,
        )
      })
    Ok(context) ->
      evaluate_exprs(
        content,
        environment.Environment(..env, value: context, parent: Some(env)),
        acc,
      )
  }
}

fn evaluate_inverted_section(
  path: List(String),
  content: List(parser.Expression),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  case environment.get(env, path) {
    Error(Nil) | Ok(value.Bool(False)) | Ok(value.List([])) ->
      evaluate_exprs(content, env, acc)
    _ -> acc
  }
}

fn evaluate_partial(
  name: scanner.PartialName,
  indentation: Option(String),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let name = resolve_partial_name(name, env)
  case dict.get(env.partials, name) {
    Ok(ast) ->
      evaluate_exprs(
        ast,
        environment.Environment(
          ..env,
          indentation: merge_indentation(env.indentation, indentation),
        ),
        acc,
      )
    Error(_) -> acc
  }
}

fn merge_indentation(outer: Option(String), inner: Option(String)) {
  case outer, inner {
    _, None -> None
    None, Some(ws) -> Some(ws)
    Some(outer), Some(inner) -> Some(outer <> inner)
  }
}

fn resolve_partial_name(
  name: scanner.PartialName,
  env: environment.Environment,
) -> String {
  case name {
    scanner.StaticName(name) -> name
    scanner.DynamicName(path) -> environment.get_and_format(env, path)
  }
}
