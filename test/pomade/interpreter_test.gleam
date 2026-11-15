import gleam/dict
import gleam/option.{None, Some}
import gleam/string_tree

import pomade/internal/interpreter
import pomade/internal/parser
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

pub fn section_test() {
  assert "hello"
    == interpreter.interpret(
      [
        parser.Section(["section"], [
          parser.LineStart(None),
          parser.Literal("hello"),
        ]),
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
        parser.Section(["sec"], [
          parser.Variable(["a"]),
          parser.Literal(", "),
          parser.Variable(["b"]),
          parser.Literal(", "),
          parser.Variable(["c", "d"]),
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
        parser.Section(["repo"], [
          parser.Literal("  <b>"),
          parser.Variable(["name"]),
          parser.Literal("</b>"),
        ]),
        parser.InvertedSection(["repo"], [
          parser.Literal("No repos :("),
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
          parser.LineStart(None),
          parser.Literal(">\n"),
          parser.LineStart(None),
          parser.Literal(">"),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn nested_partial_test() {
  assert " foo\n bar\n   baz\n   qux\nquux"
    == interpreter.interpret(
      [
        parser.Partial(scanner.StaticName("one"), Some(" ")),
        parser.Literal("quux"),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("one", [
          parser.LineStart(None),
          parser.Literal("foo\n"),
          parser.LineStart(None),
          parser.Literal("bar\n"),
          parser.Partial(scanner.StaticName("two"), Some("  ")),
        ]),
        #("two", [
          parser.LineStart(None),
          parser.Literal("baz\n"),
          parser.LineStart(None),
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
        parser.InlineParameter("block", [
          parser.Literal("foo, bar, baz"),
        ]),
      ],
      value.Dict(dict.new()),
      dict.new(),
    )
    |> string_tree.to_string()
}

pub fn indentation_at_template_expansion_test() {
  assert "    foo"
    == interpreter.interpret(
      [parser.Partial(scanner.StaticName("partial"), Some("    "))],
      value.Dict(dict.new()),
      dict.from_list([
        #("partial", [parser.LineStart(None), parser.Literal("foo")]),
      ]),
    )
    |> string_tree.to_string()

  assert "    foo"
    == interpreter.interpret(
      [parser.Parent("parent", Some("    "), [])],
      value.Dict(dict.new()),
      dict.from_list([
        #("parent", [parser.LineStart(None), parser.Literal("foo")]),
      ]),
    )
    |> string_tree.to_string()

  assert "    foo"
    == interpreter.interpret(
      [
        parser.Parameter("block", Some("    "), [
          parser.LineStart(None),
          parser.Literal("foo"),
        ]),
      ],
      value.Dict(dict.new()),
      dict.new(),
    )
    |> string_tree.to_string()

  assert "a    foo"
    == interpreter.interpret(
      [
        parser.Literal("a"),
        parser.InlineParent("parent", [
          parser.Argument("block", [
            parser.LineStart(None),
            parser.Literal("foo"),
          ]),
        ]),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("parent", [
          parser.Parameter("block", Some("    "), [
            parser.LineStart(None),
          ]),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn canonical_whitespace_model_test() {
  let intermediate = #("intermediate", [
    parser.LineStart(None),
    parser.Literal("Hi,\n"),
    parser.Parent("invitation", Some("    "), []),
  ])
  assert "Hi,\n    please give me a:\n        high five\n"
    == interpreter.interpret(
      [
        parser.Parent("intermediate", None, [
          parser.Argument("greeting", [
            parser.LineStart(None),
            parser.Literal("high five\n"),
          ]),
        ]),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        intermediate,
        #("invitation", [
          parser.LineStart(None),
          parser.Literal("please give me a:\n"),
          parser.Parameter("greeting", Some("    "), [
            parser.LineStart(None),
            parser.Literal("hug\n"),
          ]),
        ]),
      ]),
    )
    |> string_tree.to_string()

  assert "Hi,\n    please give me a:\n            high five\n"
    == interpreter.interpret(
      [
        parser.Parent("intermediate", None, [
          parser.Argument("greeting", [
            parser.LineStart(None),
            parser.Literal("high five\n"),
          ]),
        ]),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        intermediate,
        #("invitation", [
          parser.LineStart(None),
          parser.Literal("please give me a:\n"),
          parser.Parameter("greeting", Some("        "), [
            parser.LineStart(None),
            parser.Literal("hug\n"),
          ]),
        ]),
      ]),
    )
    |> string_tree.to_string()

  assert "Hi,\n    please give me a:\n        high five\n"
    == interpreter.interpret(
      [
        parser.Parent("intermediate", None, [
          parser.Argument("greeting", [
            parser.LineStart(None),
            parser.Literal("high five\n"),
          ]),
        ]),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        intermediate,
        #("invitation", [
          parser.LineStart(None),
          parser.Literal("please give me a:\n"),
          parser.Parameter("greeting", Some("    "), [
            parser.LineStart(None),
            parser.Literal("hug"),
          ]),
        ]),
      ]),
    )
    |> string_tree.to_string()

  assert "  foobar\n  baz"
    == interpreter.interpret(
      [
        parser.LineStart(None),
        parser.Partial(scanner.StaticName("partial"), Some("  ")),
      ],
      value.Dict(dict.new()),
      dict.from_list([
        #("partial", [
          parser.LineStart(None),
          parser.Literal("foo"),
          parser.InlineParameter("block", [parser.Literal("bar")]),
          parser.Literal("\n"),
          parser.LineStart(None),
          parser.Literal("baz"),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

pub fn inline_parameter_in_indented_partial_test() {
  assert "  ax\n  y\n"
    == interpreter.interpret(
      [parser.Partial(scanner.StaticName("partial"), Some("  "))],
      value.Dict(dict.new()),
      dict.from_list([
        #("partial", [
          parser.LineStart(None),
          parser.Literal("a"),
          parser.InlineParameter("block", [
            parser.Literal("x\n"),
            parser.LineStart(None),
            parser.Literal("y"),
          ]),
          parser.Literal("\n"),
        ]),
      ]),
    )
    |> string_tree.to_string()
}

// we need an indentation pass on each eval, to merge
// indents with blocks and parents and partials
// and we need to undo the stuff I did changing
// standalones to inlines
pub fn extrinsic_indentation_in_partial_test() {
  assert "   first\n    second"
    == interpreter.interpret(
      [parser.Partial(scanner.StaticName("partial"), Some(" "))],
      value.Dict(dict.new()),
      dict.from_list([
        #("partial", [
          parser.Parameter("block", Some("  "), [
            parser.Literal("first\n"),
            parser.LineStart(None),
            parser.Literal("second"),
          ]),
        ]),
      ]),
    )
    |> string_tree.to_string()
}
