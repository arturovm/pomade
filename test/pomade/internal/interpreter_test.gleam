import gleam/dict

import pomade.{String}

pub fn empty_test() {
  let assert Ok("") = pomade.interpret([], dict.new())
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    pomade.interpret([pomade.Text("hello, world!")], dict.new())
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
      dict.new(),
    )
}

pub fn variable_test() {
  let assert Ok("hello, world!") =
    pomade.interpret(
      [pomade.Variable(["foo"])],
      dict.from_list([#("foo", String("hello, world!"))]),
    )
}
