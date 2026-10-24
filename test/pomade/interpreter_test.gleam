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
      [parser.Literal("hello, world!")],
      Dict(dict.new()),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn newline_test() {
  assert "foo\nbar\r\nbaz"
    == interpreter.interpret(
      [
        parser.Literal("foo\nbar\r\nbaz"),
      ],
      Dict(dict.new()),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn variable_test() {
  assert "foo &amp; bar"
    == interpreter.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      dict.new(),
    )
    |> string_tree.to_string()

  assert "1.21"
    == interpreter.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", Float(1.21))])),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn raw_variable_test() {
  assert "foo & bar"
    == interpreter.interpret(
      [parser.RawVariable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn section_with_standalone_end_test() {
  assert "hello\n"
    == interpreter.interpret(
      [
        parser.Section(
          ["section"],
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
          [parser.Indent, parser.Literal("hello")],
        ),
      ],
      Dict(dict.from_list([#("section", String("foo"))])),
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
        parser.Section(
          ["sec"],
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
          [
            parser.Variable(["a"]),
            parser.Literal(", "),
            parser.Variable(["b"]),
            parser.Literal(", "),
            parser.Variable(["c", "d"]),
          ],
        ),
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
        parser.Section(
          ["repo"],
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
          [
            parser.Literal("  <b>"),
            parser.Variable(["name"]),
            parser.Literal("</b>"),
          ],
        ),
        parser.InvertedSection(
          ["repo"],
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
          [
            parser.Literal("No repos :("),
          ],
        ),
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
        parser.Literal("Hello, "),
        parser.Partial(scanner.StaticName("other_template"), None),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("other_template", [
          parser.Literal("world!"),
        ]),
      ]),
    )
    |> string_tree.to_string()

  assert "Hello, foo!"
    == interpreter.interpret(
      [
        parser.Literal("Hello, "),
        parser.Partial(scanner.StaticName("other_template"), None),
      ],
      value.Dict(dict.from_list([#("greeting", value.String("foo!"))])),
      dict.from_list([
        #("other_template", [
          parser.Variable(["greeting"]),
        ]),
      ]),
    )
    |> string_tree.to_string()

  assert "  >\n  >>"
    == interpreter.interpret(
      [
        parser.Partial(scanner.StaticName("partial"), Some("  ")),
        parser.Literal(">"),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("partial", [
          parser.Indent,
          parser.Literal(">\n"),
          parser.Indent,
          parser.Literal(">"),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn nested_partial_test() {
  assert "  foo\n  bar\n   \tbaz\n   \tqux\nquux"
    == interpreter.interpret(
      [
        parser.Partial(scanner.StaticName("one"), Some("  ")),
        parser.Literal("quux"),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("one", [
          parser.Indent,
          parser.Literal("foo\n"),
          parser.Indent,
          parser.Literal("bar\n"),
          parser.Partial(scanner.StaticName("two"), Some(" \t")),
        ]),
        #("two", [
          parser.Indent,
          parser.Literal("baz\n"),
          parser.Indent,
          parser.Literal("qux\n"),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn partial_with_dynamic_name_test() {
  assert "Hello, world!"
    == interpreter.interpret(
      [
        parser.Literal("Hello, "),
        parser.Partial(scanner.DynamicName(["one", "two", "three"]), None),
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
        #("other_template", [parser.Literal("world!")]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn block_test() {
  assert "foo, bar, baz"
    == interpreter.interpret(
      [
        parser.Parameter(
          "block",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
          None,
          [
            parser.Literal("foo, bar, baz"),
          ],
        ),
      ],
      value.Dict(dict.new()),
      dict.new(),
    )
    |> string_tree.to_string()
}
