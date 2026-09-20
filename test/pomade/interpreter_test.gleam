import gleam/dict

import pomade.{Dict, Float, String}

pub fn empty_test() {
  let assert Ok("") = pomade.interpret([], Dict(dict.new()))
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    pomade.interpret([pomade.Text("hello, world!")], Dict(dict.new()))
}

pub fn newline_test() {
  let assert Ok("foo\nbar\r\nbaz") =
    pomade.interpret(
      [
        pomade.Text("foo"),
        pomade.Newline("\n"),
        pomade.Text("bar"),
        pomade.Newline("\r\n"),
        pomade.Text("baz"),
      ],
      Dict(dict.new()),
    )
}

pub fn variable_test() {
  let assert Ok("foo &amp; bar") =
    pomade.interpret(
      [pomade.Variable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
    )

  let assert Ok("1.21") =
    pomade.interpret(
      [pomade.Variable(["foo"])],
      Dict(dict.from_list([#("foo", Float(1.21))])),
    )
}

pub fn raw_variable_test() {
  let assert Ok("foo & bar") =
    pomade.interpret(
      [pomade.RawVariable(["foo"])],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
    )
}
