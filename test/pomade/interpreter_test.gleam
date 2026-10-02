import gleam/dict
import gleam/option.{None, Some}
import gleam/result
import gleam/string_tree

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/value.{Dict, Float, String}

pub fn empty_test() {
  let assert Ok("") =
    interpreter.interpret([], Dict(dict.new()), dict.new())
    |> result.map(string_tree.to_string)
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    interpreter.interpret(
      [parser.Literal(rewriter.Literal(0, "hello, world!"))],
      Dict(dict.new()),
      dict.new(),
    )
    |> result.map(string_tree.to_string)
}

pub fn newline_test() {
  let assert Ok("foo\nbar\r\nbaz") =
    interpreter.interpret(
      [
        parser.Literal(rewriter.Literal(0, "foo\nbar\r\nbaz")),
      ],
      Dict(dict.new()),
      dict.new(),
    )
    |> result.map(string_tree.to_string)
}

pub fn variable_test() {
  let assert Ok("foo &amp; bar") =
    interpreter.interpret(
      [parser.Variable(rewriter.Variable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      dict.new(),
    )
    |> result.map(string_tree.to_string)

  let assert Ok("1.21") =
    interpreter.interpret(
      [parser.Variable(rewriter.Variable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", Float(1.21))])),
      dict.new(),
    )
    |> result.map(string_tree.to_string)
}

pub fn raw_variable_test() {
  let assert Ok("foo & bar") =
    interpreter.interpret(
      [parser.RawVariable(rewriter.RawVariable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      dict.new(),
    )
    |> result.map(string_tree.to_string)
}

pub fn section_with_parent_context_test() {
  let parent_env =
    value.Dict(
      dict.from_list([
        #("a", value.String("foo")),
        #("b", value.String("wrong")),
        #(
          "sec",
          value.Dict(
            dict.from_list([
              #("b", value.String("bar")),
            ]),
          ),
        ),
        #(
          "c",
          value.Dict(
            dict.from_list([
              #("d", value.String("baz")),
            ]),
          ),
        ),
      ]),
    )
  let assert Ok("foo, bar, baz") =
    interpreter.interpret(
      [
        parser.Section(rewriter.SectionStart(0, ["sec"]), [
          parser.Variable(rewriter.Variable(0, ["a"])),
          parser.Literal(rewriter.Literal(0, ", ")),
          parser.Variable(rewriter.Variable(0, ["b"])),
          parser.Literal(rewriter.Literal(0, ", ")),
          parser.Variable(rewriter.Variable(0, ["c", "d"])),
        ]),
      ],
      parent_env,
      dict.new(),
    )
    |> result.map(string_tree.to_string)
}

pub fn inverted_section_test() {
  let assert Ok("No repos :(") =
    interpreter.interpret(
      [
        parser.Section(rewriter.SectionStart(0, ["repo"]), [
          parser.Literal(rewriter.Literal(0, "  <b>")),
          parser.Variable(rewriter.Variable(0, ["name"])),
          parser.Literal(rewriter.Literal(0, "</b>")),
        ]),
        parser.InvertedSection(rewriter.InvertedSectionStart(0, ["repo"]), [
          parser.Literal(rewriter.Literal(0, "No repos :(")),
        ]),
      ],
      Dict(dict.from_list([#("repo", value.List([]))])),
      dict.new(),
    )
    |> result.map(string_tree.to_string)
}

pub fn partial_test() {
  let assert Ok("Hello, world!") =
    interpreter.interpret(
      [
        parser.Literal(rewriter.Literal(0, "Hello, ")),
        parser.Partial(rewriter.Partial(0, "other_template"), None),
      ],
      value.Dict(dict.new()),
      dict.from_list([#("other_template", "world!")]),
    )
    |> result.map(string_tree.to_string)
  let assert Ok("Hello, foo!") =
    interpreter.interpret(
      [
        parser.Literal(rewriter.Literal(0, "Hello, ")),
        parser.Partial(rewriter.Partial(0, "other_template"), None),
      ],
      value.Dict(dict.from_list([#("greeting", value.String("foo!"))])),
      dict.from_list([#("other_template", "{{greeting}}")]),
    )
    |> result.map(string_tree.to_string)
  let assert Ok("  >\n  >>") =
    interpreter.interpret(
      [
        parser.Partial(rewriter.Partial(0, "partial"), Some("  ")),
        parser.Literal(rewriter.Literal(0, ">")),
      ],
      value.Dict(dict.new()),
      dict.from_list([#("partial", ">\n>")]),
    )
    |> result.map(string_tree.to_string)
}
