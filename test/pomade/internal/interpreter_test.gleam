import pomade/internal/interpreter
import pomade/internal/parser

pub fn empty_test() {
  let assert Ok("") = interpreter.interpret(parser.Template([]))
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    interpreter.interpret(parser.Template([parser.Text("hello, world!")]))
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
    )
}
