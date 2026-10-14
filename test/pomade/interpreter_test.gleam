import gleam/dict
import gleam/option.{None, Some}
import gleam/string_tree

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner
import pomade/internal/value.{Dict, Float, String}

pub fn empty_test() {
  assert ""
    == interpreter.interpret([], Dict(dict.new()), dict.new())
    |> string_tree.to_string()
}

pub fn text_test() {
  assert "hello, world!"
    == interpreter.interpret(
      [parser.Literal(rewriter.Literal(0, "hello, world!"))],
      Dict(dict.new()),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn newline_test() {
  assert "foo\nbar\r\nbaz"
    == interpreter.interpret(
      [
        parser.Literal(rewriter.Literal(0, "foo\nbar\r\nbaz")),
      ],
      Dict(dict.new()),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn variable_test() {
  assert "foo &amp; bar"
    == interpreter.interpret(
      [parser.Variable(rewriter.Variable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      dict.new(),
    )
    |> string_tree.to_string()

  assert "1.21"
    == interpreter.interpret(
      [parser.Variable(rewriter.Variable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", Float(1.21))])),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn raw_variable_test() {
  assert "foo & bar"
    == interpreter.interpret(
      [parser.RawVariable(rewriter.RawVariable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      dict.new(),
    )
    |> string_tree.to_string()
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
  assert "foo, bar, baz"
    == interpreter.interpret(
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
    |> string_tree.to_string()
}

pub fn inverted_section_test() {
  assert "No repos :("
    == interpreter.interpret(
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
    |> string_tree.to_string()
}

pub fn partial_test() {
  assert "Hello, world!"
    == interpreter.interpret(
      [
        parser.Literal(rewriter.Literal(0, "Hello, ")),
        parser.Partial(
          rewriter.Partial(0, scanner.StaticName("other_template")),
          None,
        ),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("other_template", [
          parser.Literal(rewriter.Literal(0, "world!")),
        ]),
      ]),
    )
    |> string_tree.to_string()

  assert "Hello, foo!"
    == interpreter.interpret(
      [
        parser.Literal(rewriter.Literal(0, "Hello, ")),
        parser.Partial(
          rewriter.Partial(0, scanner.StaticName("other_template")),
          None,
        ),
      ],
      value.Dict(dict.from_list([#("greeting", value.String("foo!"))])),
      dict.from_list([
        #("other_template", [
          parser.Variable(rewriter.Variable(0, ["greeting"])),
        ]),
      ]),
    )
    |> string_tree.to_string()

  assert "  >\n  >>"
    == interpreter.interpret(
      [
        parser.Partial(
          rewriter.Partial(0, scanner.StaticName("partial")),
          Some("  "),
        ),
        parser.Literal(rewriter.Literal(0, ">")),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("partial", [
          parser.Indent,
          parser.Literal(rewriter.Literal(0, ">\n")),
          parser.Indent,
          parser.Literal(rewriter.Literal(1, ">")),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn nested_partial_test() {
  assert "  foo\n  bar\n   \tbaz\n   \tqux\nquux"
    == interpreter.interpret(
      [
        parser.Partial(
          rewriter.Partial(0, scanner.StaticName("one")),
          Some("  "),
        ),
        parser.Literal(rewriter.Literal(0, "quux")),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("one", [
          parser.Indent,
          parser.Literal(rewriter.Literal(0, "foo\n")),
          parser.Indent,
          parser.Literal(rewriter.Literal(1, "bar\n")),
          parser.Partial(
            rewriter.Partial(0, scanner.StaticName("two")),
            Some(" \t"),
          ),
        ]),
        #("two", [
          parser.Indent,
          parser.Literal(rewriter.Literal(0, "baz\n")),
          parser.Indent,
          parser.Literal(rewriter.Literal(0, "qux\n")),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn partial_with_dynamic_name_test() {
  assert "Hello, world!"
    == interpreter.interpret(
      [
        parser.Literal(rewriter.Literal(0, "Hello, ")),
        parser.Partial(
          rewriter.Partial(0, scanner.DynamicName(["one", "two", "three"])),
          None,
        ),
      ],
      value.Dict(
        dict.from_list([
          #(
            "one",
            value.Dict(
              dict.from_list([
                #(
                  "two",
                  value.Dict(
                    dict.from_list([#("three", value.String("other_template"))]),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
      dict.from_list([
        #("other_template", [parser.Literal(rewriter.Literal(0, "world!"))]),
      ]),
    )
    |> string_tree.to_string()
}
