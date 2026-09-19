import gleam/dict
import gleam/option.{Some}

import pomade.{Dict, String}

pub fn empty_test() {
  let assert Ok("") = pomade.interpret([], Some(Dict(dict.new())))
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    pomade.interpret([pomade.Text("hello, world!")], Some(Dict(dict.new())))
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
      Some(Dict(dict.new())),
    )
}

pub fn variable_test() {
  let assert Ok("hello, world!") =
    pomade.interpret(
      [pomade.Variable(["foo"])],
      Some(Dict(dict.from_list([#("foo", Some(String("hello, world!")))]))),
    )
}
