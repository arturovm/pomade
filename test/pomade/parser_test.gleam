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
      scanner.LeftDelimiter,
      scanner.Identifier("hello"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn dotted_variable_test() {
  let assert Ok([parser.Variable(["hello", "world"])]) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.Identifier("hello"),
      scanner.Dot,
      scanner.Identifier("world"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok([parser.Variable(["."])]) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.Dot,
      scanner.RightDelimiter,
      scanner.Eof,
    ])

  let assert Error(parser.UnexpectedTokenError(scanner.Identifier("foo"))) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.Dot,
      scanner.Identifier("foo"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn raw_variable_test() {
  let assert Ok([parser.RawVariable(["hello"])]) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.RawVariable,
      scanner.Identifier("hello"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])

  let assert Ok([parser.RawVariable(["goodbye"])]) =
    parser.parse([
      scanner.LeftTripleMustache,
      scanner.Identifier("goodbye"),
      scanner.RightTripleMustache,
      scanner.Eof,
    ])
}

pub fn section_test() {
  let assert Ok([parser.Section(["person"], [parser.Variable(["name"])])]) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.SectionStart,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.Identifier("name"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.End,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
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
      scanner.LeftDelimiter,
      scanner.InvertedSectionStart,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.Text("no"),
      scanner.Whitespace(" "),
      scanner.Text("repos"),
      scanner.Whitespace(" "),
      scanner.Text(":("),
      scanner.LeftDelimiter,
      scanner.End,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn partial_test() {
  let assert Ok([parser.Partial(["box"])]) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.Partial,
      scanner.Identifier("box"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn block_test() {
  let assert Ok([parser.Block(["title"], [parser.Text("hello, world!")])]) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.BlockStart,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.Text("hello, world!"),
      scanner.LeftDelimiter,
      scanner.End,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn parent_test() {
  let assert Ok([parser.Parent(["title"], [parser.Text("foo, bar, baz")])]) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.ParentStart,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.Text("foo, bar, baz"),
      scanner.LeftDelimiter,
      scanner.End,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
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
      scanner.LeftDelimiter,
      scanner.SectionStart,
      scanner.Identifier("a_section"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.Identifier("some_variable"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.InvertedSectionStart,
      scanner.Identifier("inner_section"),
      scanner.RightDelimiter,
      scanner.Text("inner text"),
      scanner.LeftDelimiter,
      scanner.End,
      scanner.Identifier("inner_section"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.End,
      scanner.Identifier("a_section"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}
