import gleam/dict

import pomade/value.{Dict, Float, String}

import pomade/internal/interpreter
import pomade/internal/parser

pub fn empty_test() {
  let assert Ok("") = interpreter.interpret([], Dict(dict.new()))
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    interpreter.interpret([parser.Text("hello, world!")], Dict(dict.new()))
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
    )
}

pub fn variable_test() {
  let assert Ok("foo &amp; bar") =
    interpreter.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
    )

  let assert Ok("1.21") =
    interpreter.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", Float(1.21))])),
    )
}

pub fn raw_variable_test() {
  let assert Ok("foo & bar") =
    interpreter.interpret(
      [parser.RawVariable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
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
    )
}
