import gleam/dict
import gleam/option.{None, Some}

import pomade/internal/interpreter
import pomade/internal/parser
import pomade/internal/scanner
import pomade/internal/value.{Dict, Float, String}

pub fn empty_test() {
  let assert Ok("") = interpreter.interpret([], Dict(dict.new()), None)
}

pub fn text_test() {
  let assert Ok("hello, world!") =
    interpreter.interpret(
      [parser.Text(scanner.Text(0, "hello, world!"))],
      Dict(dict.new()),
      None,
    )
}

pub fn newline_test() {
  let assert Ok("foo\nbar\r\nbaz") =
    interpreter.interpret(
      [
        parser.Text(scanner.Text(0, "foo")),
        parser.Newline(scanner.Newline(0, "\n")),
        parser.Text(scanner.Text(0, "bar")),
        parser.Newline(scanner.Newline(0, "\r\n")),
        parser.Text(scanner.Text(0, "baz")),
      ],
      Dict(dict.new()),
      None,
    )
}

pub fn variable_test() {
  let assert Ok("foo &amp; bar") =
    interpreter.interpret(
      [parser.Variable(scanner.Variable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", String("foo & bar"))])),
      None,
    )

  let assert Ok("1.21") =
    interpreter.interpret(
      [parser.Variable(scanner.Variable(0, ["foo"]))],
      Dict(dict.from_list([#("foo", Float(1.21))])),
      None,
    )
}

pub fn raw_variable_test() {
  let assert Ok("foo & bar") =
    interpreter.interpret(
      [parser.RawVariable(scanner.RawVariable(0, ["foo"]))],
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
        parser.Section(scanner.SectionStart(0, ["sec"]), [
          parser.Variable(scanner.Variable(0, ["a"])),
          parser.Text(scanner.Text(0, ", ")),
          parser.Variable(scanner.Variable(0, ["b"])),
          parser.Text(scanner.Text(0, ", ")),
          parser.Variable(scanner.Variable(0, ["c", "d"])),
        ]),
      ],
      parent_env,
      None,
    )
}

pub fn inverted_section_test() {
  let assert Ok("No repos :(") =
    interpreter.interpret(
      [
        parser.Section(scanner.SectionStart(0, ["repo"]), [
          parser.Whitespace(scanner.Whitespace(0, "  ")),
          parser.Text(scanner.Text(0, "<b>")),
          parser.Variable(scanner.Variable(0, ["name"])),
          parser.Text(scanner.Text(0, "</b>")),
        ]),
        parser.InvertedSection(scanner.InvertedSectionStart(0, ["repo"]), [
          parser.Text(scanner.Text(0, "No repos :(")),
        ]),
      ],
      Dict(dict.from_list([#("repo", value.from_list([]))])),
      None,
    )
}

pub fn partial_test() {
  let assert Ok("Hello, world!") =
    interpreter.interpret(
      [
        parser.Text(scanner.Text(0, "Hello,")),
        parser.Whitespace(scanner.Whitespace(0, " ")),
        parser.Partial(scanner.Partial(0, "other_template"), None),
      ],
      value.Dict(dict.new()),
      Some(dict.from_list([#("other_template", "world!")])),
    )
  let assert Ok("Hello, foo!") =
    interpreter.interpret(
      [
        parser.Text(scanner.Text(0, "Hello,")),
        parser.Whitespace(scanner.Whitespace(0, " ")),
        parser.Partial(scanner.Partial(0, "other_template"), None),
      ],
      value.Dict(dict.from_list([#("greeting", value.String("foo!"))])),
      Some(dict.from_list([#("other_template", "{{greeting}}")])),
    )
  let assert Ok("  >\n  >>") =
    interpreter.interpret(
      [
        parser.Partial(scanner.Partial(0, "partial"), Some("  ")),
        parser.Text(scanner.Text(0, ">")),
      ],
      value.Dict(dict.new()),
      Some(dict.from_list([#("partial", ">\n>")])),
    )
}
