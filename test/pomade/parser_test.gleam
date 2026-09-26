import pomade/internal/parser
import pomade/internal/scanner

pub fn empty_parser_test() {
  let assert Ok([]) = parser.parse([scanner.Eof])
}

pub fn text_test() {
  let assert Ok([
    parser.Text("hello,"),
    parser.Whitespace(" "),
    parser.Text("world!"),
  ]) =
    parser.parse([
      scanner.Text("hello,"),
      scanner.Whitespace(" "),
      scanner.Text("world!"),
      scanner.Eof,
    ])
}

pub fn variable_test() {
  let assert Ok([parser.Variable(["hello"])]) =
    parser.parse([
      scanner.Variable(["hello"]),
      scanner.Eof,
    ])
}

pub fn dotted_variable_test() {
  let assert Ok([parser.Variable(["hello", "world"])]) =
    parser.parse([
      scanner.Variable(["hello", "world"]),
      scanner.Eof,
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok([parser.Variable(["."])]) =
    parser.parse([
      scanner.Variable(["."]),
      scanner.Eof,
    ])
}

pub fn raw_variable_test() {
  let assert Ok([parser.RawVariable(["hello"])]) =
    parser.parse([
      scanner.RawVariable(["hello"]),
      scanner.Eof,
    ])

  let assert Ok([parser.RawVariable(["goodbye"])]) =
    parser.parse([
      scanner.RawVariable(["goodbye"]),
      scanner.Eof,
    ])
}

pub fn section_test() {
  let assert Ok([parser.Section(["person"], [parser.Variable(["name"])])]) =
    parser.parse([
      scanner.SectionStart(["person"]),
      scanner.Variable(["name"]),
      scanner.End(["person"]),
      scanner.Eof,
    ])
}

pub fn inverted_section_test() {
  let assert Ok([
    parser.InvertedSection(
      ["person"],
      [
        parser.Text("no"),
        parser.Whitespace(" "),
        parser.Text("repos"),
        parser.Whitespace(" "),
        parser.Text(":("),
      ],
    ),
  ]) =
    parser.parse([
      scanner.InvertedSectionStart(["person"]),
      scanner.Text("no"),
      scanner.Whitespace(" "),
      scanner.Text("repos"),
      scanner.Whitespace(" "),
      scanner.Text(":("),
      scanner.End(["person"]),
      scanner.Eof,
    ])
}

pub fn partial_test() {
  let assert Ok([parser.Partial("box")]) =
    parser.parse([
      scanner.Partial("box"),
      scanner.Eof,
    ])
}

pub fn block_test() {
  let assert Ok([parser.Block(["title"], [parser.Text("hello, world!")])]) =
    parser.parse([
      scanner.BlockStart(["title"]),
      scanner.Text("hello, world!"),
      scanner.End(["title"]),
      scanner.Eof,
    ])
}

pub fn parent_test() {
  let assert Ok([parser.Parent(["title"], [parser.Text("foo, bar, baz")])]) =
    parser.parse([
      scanner.ParentStart(["title"]),
      scanner.Text("foo, bar, baz"),
      scanner.End(["title"]),
      scanner.Eof,
    ])
}

pub fn recursion_test() {
  let assert Ok([
    parser.Text("some text"),
    parser.Section(
      ["a_section"],
      [
        parser.Variable(["some_variable"]),
        parser.InvertedSection(["inner_section"], [parser.Text("inner text")]),
      ],
    ),
  ]) =
    parser.parse([
      scanner.Text("some text"),
      scanner.SectionStart(["a_section"]),
      scanner.Variable(["some_variable"]),
      scanner.InvertedSectionStart(["inner_section"]),
      scanner.Text("inner text"),
      scanner.End(["inner_section"]),
      scanner.End(["a_section"]),
      scanner.Eof,
    ])
}
