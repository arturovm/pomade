import gleam/dict

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/value.{String}

pub fn empty_test() {
  let assert Ok("") = interpreter.interpret(parser.Template([]), dict.new())
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    interpreter.interpret(
      parser.Template([parser.Text("hello, world!")]),
      dict.new(),
    )
}

pub fn newline_test() {
  let assert Ok("foo\nbar\r\nbaz") =
    interpreter.interpret(
      parser.Template([
        parser.Text("foo"),
        parser.Newline("\n"),
        parser.Text("bar"),
        parser.Newline("\r\n"),
        parser.Text("baz"),
      ]),
      dict.new(),
    )
}

pub fn variable_test() {
  let assert Ok("hello, world!") =
    interpreter.interpret(
      parser.Template([parser.Variable(["foo"])]),
      dict.from_list([#("foo", String("hello, world!"))]),
    )
}
