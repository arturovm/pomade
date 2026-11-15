import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string_tree.{type StringTree}

import pomade/internal/environment
import pomade/internal/parser
import pomade/internal/scanner
import pomade/internal/value

pub fn interpret(
  template: List(parser.Expression),
  environment: value.Value,
  templates: Dict(String, List(parser.Expression)),
) -> StringTree {
  evaluate_exprs(
    template,
    environment.Environment(environment, templates, dict.new(), None),
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
    [parser.LineStart(value), ..tail] ->
      evaluate_exprs(tail, env, evaluate_line_start(value, acc))
    [parser.Literal(value), ..tail] ->
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
    [parser.Section(path, content), ..tail] ->
      evaluate_exprs(tail, env, evaluate_section(path, content, env, acc))
    [parser.InvertedSection(path, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_inverted_section(path, content, env, acc),
      )
    [parser.Partial(name, indentation), ..tail] ->
      evaluate_exprs(tail, env, evaluate_partial(name, indentation, env, acc))
    [parser.InlinePartial(name), ..tail] ->
      evaluate_exprs(tail, env, evaluate_inline_partial(name, env, acc))
    [parser.InlineParameter(name, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_inline_parameter(name, content, env, acc),
      )
    [parser.Parameter(name, indentation, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_standalone_parameter(name, indentation, content, env, acc),
      )
    [parser.InlineParent(name, content), ..tail] ->
      evaluate_exprs(tail, env, evaluate_inline_parent(name, content, env, acc))
    [parser.Parent(name, indentation, content), ..tail] ->
      evaluate_exprs(
        tail,
        env,
        evaluate_standalone_parent(name, indentation, content, env, acc),
      )
  }
}

fn evaluate_line_start(leading: Option(String), acc: StringTree) -> StringTree {
  case leading {
    Some(leading) -> string_tree.append(acc, leading)
    None -> acc
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
  case dict.get(env.templates, name) {
    Ok(ast) -> {
      let ast = apply_indentation(ast, indentation)
      evaluate_exprs(ast, env, acc)
    }
    Error(_) -> acc
  }
}

fn apply_indentation(
  exprs: List(parser.Expression),
  indentation: Option(String),
) -> List(parser.Expression) {
  case indentation {
    Some(indentation) -> apply_indentation_loop(exprs, indentation, [])
    None -> exprs
  }
}

fn apply_indentation_loop(
  exprs: List(parser.Expression),
  indentation: String,
  acc: List(parser.Expression),
) -> List(parser.Expression) {
  case exprs {
    [] -> list.reverse(acc)
    [parser.LineStart(leading), ..tail] -> {
      apply_indentation_loop(tail, indentation, [
        parser.LineStart(indent(indentation, leading)),
        ..acc
      ])
    }
    [parser.Partial(name, partial_indentation), ..tail] -> {
      apply_indentation_loop(tail, indentation, [
        parser.Partial(name, indent(indentation, partial_indentation)),
        ..acc
      ])
    }
    [parser.Parent(name, parent_indentation, arguments), ..tail] -> {
      apply_indentation_loop(tail, indentation, [
        parser.Parent(name, indent(indentation, parent_indentation), arguments),
        ..acc
      ])
    }
    [parser.Parameter(name, parameter_indentation, content), ..tail] -> {
      apply_indentation_loop(tail, indentation, [
        parser.Parameter(
          name,
          indent(indentation, parameter_indentation),
          apply_indentation_loop(content, indentation, []),
        ),
        ..acc
      ])
    }
    [parser.InlineParameter(name, content), ..tail] -> {
      apply_indentation_loop(tail, indentation, [
        parser.InlineParameter(
          name,
          apply_indentation_loop(content, indentation, []),
        ),
        ..acc
      ])
    }
    [head, ..tail] -> apply_indentation_loop(tail, indentation, [head, ..acc])
  }
}

fn evaluate_inline_partial(
  name: scanner.PartialName,
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let name = resolve_partial_name(name, env)
  case dict.get(env.templates, name) {
    Ok(ast) -> evaluate_exprs(ast, env, acc)
    Error(_) -> acc
  }
}

fn indent(outer: String, inner: Option(String)) {
  case inner {
    None -> Some(outer)
    Some(inner) -> Some(outer <> inner)
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

fn evaluate_inline_parameter(
  name: String,
  content: List(parser.Expression),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let content = case dict.get(env.arguments, name) {
    Error(_) -> content
    Ok(override) -> override
  }
  evaluate_exprs(content, env, acc)
}

fn evaluate_standalone_parameter(
  name: String,
  indentation: Option(String),
  content: List(parser.Expression),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  let content = case dict.get(env.arguments, name) {
    Error(_) -> content
    Ok(override) -> override
  }
  let content = apply_indentation(content, indentation)
  // A block's content is essentially an "inline template", so we have to ensure
  // that it has a line start. We only need to do this when the start tag
  // doesn't clear at the end, because otherwise the rewriter will have taken
  // care of this for us.
  let content = case content {
    [parser.LineStart(_), ..] -> content
    content -> [parser.LineStart(indentation), ..content]
  }
  evaluate_exprs(content, env, acc)
}

fn evaluate_inline_parent(
  name: String,
  content: List(parser.Argument),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  case dict.get(env.templates, name) {
    Ok(ast) ->
      evaluate_exprs(
        ast,
        environment.Environment(
          ..env,
          arguments: find_arguments_in_parent(content, env.arguments),
        ),
        acc,
      )
    Error(_) -> acc
  }
}

fn evaluate_standalone_parent(
  name: String,
  indentation: Option(String),
  content: List(parser.Argument),
  env: environment.Environment,
  acc: StringTree,
) -> StringTree {
  case dict.get(env.templates, name) {
    Ok(ast) -> {
      let ast = apply_indentation(ast, indentation)
      evaluate_exprs(
        ast,
        environment.Environment(
          ..env,
          arguments: find_arguments_in_parent(content, env.arguments),
        ),
        acc,
      )
    }
    Error(_) -> acc
  }
}

// helpers

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
