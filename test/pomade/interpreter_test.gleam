import gleam/dict
import gleam/option.{None, Some}

import pomade/value.{Dict, Float, String}

import pomade/internal/interpreter
import pomade/internal/parser

pub fn empty_test() {
  let assert Ok("") = interpreter.interpret([], Dict(dict.new()), None)
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    interpreter.interpret(
      [parser.Text("hello, world!")],
      Dict(dict.new()),
      None,
    )
}

pub fn newline_test() {
  let assert Ok("foo\nbar\r\nbaz") =
    interpreter.interpret(
      [
        parser.Text("foo"),
        parser.Newline("\n"),
        parser.Text("bar"),
        parser.Newline("\r\n"),
        parser.Text("baz"),
      ],
      Dict(dict.new()),
      None,
    )
}

pub fn variable_test() {
  let assert Ok("foo &amp; bar") =
    interpreter.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      None,
    )

  let assert Ok("1.21") =
    interpreter.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", Float(1.21))])),
      None,
    )
}

pub fn raw_variable_test() {
  let assert Ok("foo & bar") =
    interpreter.interpret(
      [parser.RawVariable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      None,
    )
}

pub fn section_with_parent_context_test() {
  let parent_env =
    value.from_dict(
      dict.from_list([
        #("a", value.from_string("foo")),
        #("b", value.from_string("wrong")),
        #(
          "sec",
          value.from_dict(
            dict.from_list([
              #("b", value.from_string("bar")),
            ]),
          ),
        ),
        #(
          "c",
          value.from_dict(
            dict.from_list([
              #("d", value.from_string("baz")),
            ]),
          ),
        ),
      ]),
    )
  let assert Ok("foo, bar, baz") =
    interpreter.interpret(
      [
        parser.Section(["sec"], [
          parser.Variable(["a"]),
          parser.Text(", "),
          parser.Variable(["b"]),
          parser.Text(", "),
          parser.Variable(["c", "d"]),
        ]),
      ],
      parent_env,
      None,
    )
}

pub fn inverted_variable_test() {
  let assert Ok("No repos :(") =
    interpreter.interpret(
      [
        parser.Section(["repo"], [
          parser.Whitespace("  "),
          parser.Text("<b>"),
          parser.Variable(["name"]),
          parser.Text("</b>"),
        ]),
        parser.InvertedSection(["repo"], [parser.Text("No repos :(")]),
      ],
      Dict(dict.from_list([#("repo", value.from_list([]))])),
      None,
    )
}

pub fn partial_test() {
  let assert Ok("Hello, world!") =
    interpreter.interpret(
      [
        parser.Text("Hello,"),
        parser.Whitespace(" "),
        parser.Partial(["other_template"]),
      ],
      value.Dict(dict.new()),
      Some(dict.from_list([#("other_template", "world!")])),
    )
  let assert Ok("Hello, foo!") =
    interpreter.interpret(
      [
        parser.Text("Hello,"),
        parser.Whitespace(" "),
        parser.Partial(["other_template"]),
      ],
      value.Dict(dict.from_list([#("greeting", value.String("foo!"))])),
      Some(dict.from_list([#("other_template", "{{greeting}}")])),
    )
}
