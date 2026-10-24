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
  templates: Dict(String, List(parser.Expression)),
) -> StringTree {
  evaluate_exprs(
    template,
    environment.Environment(environment, None, templates, dict.new(), None),
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
    [parser.Literal(value), ..tail] ->
      evaluate_exprs(tail, env, string_tree.append(acc, value))
    [parser.Indent, ..tail] ->
      evaluate_exprs(tail, env, case env.indentation {
        None -> acc
        Some(indentation) -> string_tree.append(acc, indentation)
      })
    [parser.Leading(value), ..tail] ->
      evaluate_exprs(tail, env, string_tree.append(acc, value))
    [parser.Variable(path), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        string_tree.append(acc, evaluate_variable(path, env)),
      )
    [parser.RawVariable(path), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        string_tree.append(acc, evaluate_raw_variable(path, env)),
      )
    [parser.Section(path, end_tag, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_section(path, content, end_tag, env, acc),
      )
    [parser.InvertedSection(path, end_tag, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_inverted_section(path, content, end_tag, env, acc),
      )
    [parser.Partial(name, indentation), ..tail] ->
      evaluate_exprs(tail, env, evaluate_partial(name, indentation, env, acc))
    [parser.Parameter(name, start_tag, end_tag, indentation, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_parameter(
          name,
          indentation,
          start_tag,
          content,
          end_tag,
          env,
          acc,
        ),
      )
    [parser.Parent(name, start_tag, end_tag, indentation, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_parent(
          name,
          indentation,
          start_tag,
          content,
          end_tag,
          env,
          acc,
        ),
      )
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
  end_tag: rewriter.Clearance,
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let acc = case environment.get(env, path) {
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
  render_end_tag(acc, end_tag)
}

fn evaluate_inverted_section(
  path: List(String),
  content: List(parser.Expression),
  end_tag: rewriter.Clearance,
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let acc = case environment.get(env, path) {
    Error(Nil) | Ok(value.Bool(False)) | Ok(value.List([])) ->
      evaluate_exprs(content, env, acc)
    _ -> acc
  }
  render_end_tag(acc, end_tag)
}

fn evaluate_partial(
  name: scanner.PartialName,
  indentation: Option(String),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let name = resolve_partial_name(name, env)
  case dict.get(env.templates, name) {
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

fn evaluate_parameter(
  name: String,
  indentation: Option(String),
  start_tag: rewriter.Clearance,
  content: List(parser.Expression),
  end_tag: rewriter.Clearance,
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let content = case dict.get(env.arguments, name) {
    Error(_) -> content
    Ok(override) -> override
  }
  evaluate_exprs(
    content,
    environment.Environment(
      ..env,
      indentation: merge_indentation(env.indentation, indentation),
    ),
    acc,
  )
}

fn evaluate_parent(
  name: String,
  indentation: Option(String),
  start_tag: rewriter.Clearance,
  content: List(parser.Argument),
  end_tag: rewriter.Clearance,
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  case dict.get(env.templates, name) {
    Ok(ast) ->
      evaluate_exprs(
        ast,
        environment.Environment(
          ..env,
          indentation: merge_indentation(env.indentation, indentation),
          arguments: find_arguments_in_parent(content, env.arguments),
        ),
        acc,
      )
    Error(_) -> acc
  }
}

// helpers

fn render_end_tag(
  acc: StringTree,
  clearance: rewriter.Clearance,
) -> StringTree {
  case clearance {
    rewriter.Clearance(rewriter.Clears(_), rewriter.Clears(_)) -> acc
    rewriter.Clearance(start, end) -> {
      let acc = case start {
        rewriter.Clears(Some(leading)) -> string_tree.append(acc, leading)
        _ -> acc
      }
      case end {
        rewriter.Clears(Some(trailing)) -> string_tree.append(acc, trailing)
        _ -> acc
      }
    }
  }
}

fn find_arguments_in_parent(
  content: List(parser.Argument),
  acc: Dict(String, List(parser.Expression)),
) -> Dict(String, List(parser.Expression)) {
  case content {
    [] -> acc
    [parser.Argument(name, content), ..tail] -> {
      let acc =
        dict.upsert(acc, name, fn(val) {
          case val {
            None -> content
            Some(previous) -> previous
          }
        })
      find_arguments_in_parent(tail, acc)
    }
  }
}
