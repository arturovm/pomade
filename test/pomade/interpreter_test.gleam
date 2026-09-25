import gleam/dict

import pomade.{Dict, Float, String}
import pomade/internal/parser

pub fn empty_test() {
  let assert Ok("") = pomade.interpret([], Dict(dict.new()))
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    pomade.interpret([parser.Text("hello, world!")], Dict(dict.new()))
}

pub fn newline_test() {
  let assert Ok("foo\nbar\r\nbaz") =
    pomade.interpret(
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
    pomade.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
    )

  let assert Ok("1.21") =
    pomade.interpret(
      [parser.Variable(["foo"])],
      Dict(dict.from_list([#("foo", Float(1.21))])),
    )
}

pub fn raw_variable_test() {
  let assert Ok("foo & bar") =
    pomade.interpret(
      [parser.RawVariable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
    )
}

pub fn section_with_parent_context_test() {
  let parent_env =
    pomade.from_dict(
      dict.from_list([
        #("a", pomade.from_string("foo")),
        #("b", pomade.from_string("wrong")),
        #(
          "sec",
          pomade.from_dict(
            dict.from_list([
              #("b", pomade.from_string("bar")),
            ]),
          ),
        ),
        #(
          "c",
          pomade.from_dict(
            dict.from_list([
              #("d", pomade.from_string("baz")),
            ]),
          ),
        ),
      ]),
    )
  let assert Ok("foo, bar, baz") =
    pomade.interpret(
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
