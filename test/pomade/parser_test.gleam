import pomade/internal/parser
import pomade/internal/scanner

pub fn empty_parser_test() {
  let assert Ok([]) = parser.parse([scanner.Eof(0)])
}

pub fn text_test() {
  let assert Ok([
    parser.Text(scanner.Text(_, "hello,")),
    parser.Whitespace(scanner.Whitespace(_, " ")),
    parser.Text(scanner.Text(_, "world!")),
  ]) =
    parser.parse([
      scanner.Text(0, "hello,"),
      scanner.Whitespace(0, " "),
      scanner.Text(0, "world!"),
      scanner.Eof(0),
    ])
}

pub fn variable_test() {
  let assert Ok([parser.Variable(scanner.Variable(_, ["hello"]))]) =
    parser.parse([
      scanner.Variable(0, ["hello"]),
      scanner.Eof(0),
    ])
}

pub fn dotted_variable_test() {
  let assert Ok([parser.Variable(scanner.Variable(_, ["hello", "world"]))]) =
    parser.parse([
      scanner.Variable(0, ["hello", "world"]),
      scanner.Eof(0),
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok([parser.Variable(scanner.Variable(_, ["."]))]) =
    parser.parse([
      scanner.Variable(0, ["."]),
      scanner.Eof(0),
    ])
}

pub fn raw_variable_test() {
  let assert Ok([parser.RawVariable(scanner.RawVariable(_, ["hello"]))]) =
    parser.parse([
      scanner.RawVariable(0, ["hello"]),
      scanner.Eof(0),
    ])
}

pub fn section_test() {
  let assert Ok([
    parser.Section(
      scanner.SectionStart(_, ["person"]),
      [parser.Variable(scanner.Variable(_, ["name"]))],
    ),
  ]) =
    parser.parse([
      scanner.SectionStart(0, ["person"]),
      scanner.Variable(0, ["name"]),
      scanner.End(0, ["person"]),
      scanner.Eof(0),
    ])
}

pub fn inverted_section_test() {
  let assert Ok([
    parser.InvertedSection(
      scanner.InvertedSectionStart(_, ["person"]),
      [
        parser.Text(scanner.Text(_, "no")),
        parser.Whitespace(scanner.Whitespace(_, " ")),
        parser.Text(scanner.Text(_, "repos")),
        parser.Whitespace(scanner.Whitespace(_, " ")),
        parser.Text(scanner.Text(_, ":(")),
      ],
    ),
  ]) =
    parser.parse([
      scanner.InvertedSectionStart(0, ["person"]),
      scanner.Text(0, "no"),
      scanner.Whitespace(0, " "),
      scanner.Text(0, "repos"),
      scanner.Whitespace(0, " "),
      scanner.Text(0, ":("),
      scanner.End(0, ["person"]),
      scanner.Eof(0),
    ])
}

pub fn partial_test() {
  let assert Ok([parser.Partial(scanner.Partial(_, "box"))]) =
    parser.parse([
      scanner.Partial(0, "box"),
      scanner.Eof(0),
    ])
}

pub fn block_test() {
  let assert Ok([
    parser.Block(
      scanner.BlockStart(_, ["title"]),
      [parser.Text(scanner.Text(_, "hello, world!"))],
    ),
  ]) =
    parser.parse([
      scanner.BlockStart(0, ["title"]),
      scanner.Text(0, "hello, world!"),
      scanner.End(0, ["title"]),
      scanner.Eof(0),
    ])
}

pub fn parent_test() {
  let assert Ok([
    parser.Parent(
      scanner.ParentStart(_, ["title"]),
      [parser.Text(scanner.Text(_, "foo, bar, baz"))],
    ),
  ]) =
    parser.parse([
      scanner.ParentStart(0, ["title"]),
      scanner.Text(0, "foo, bar, baz"),
      scanner.End(0, ["title"]),
      scanner.Eof(0),
    ])
}

pub fn recursion_test() {
  let assert Ok([
    parser.Text(scanner.Text(_, "some text")),
    parser.Section(
      scanner.SectionStart(_, ["a_section"]),
      [
        parser.Variable(scanner.Variable(_, ["some_variable"])),
        parser.InvertedSection(
          scanner.InvertedSectionStart(_, ["inner_section"]),
          [parser.Text(scanner.Text(_, "inner text"))],
        ),
      ],
    ),
  ]) =
    parser.parse([
      scanner.Text(0, "some text"),
      scanner.SectionStart(0, ["a_section"]),
      scanner.Variable(0, ["some_variable"]),
      scanner.InvertedSectionStart(0, ["inner_section"]),
      scanner.Text(0, "inner text"),
      scanner.End(0, ["inner_section"]),
      scanner.End(0, ["a_section"]),
      scanner.Eof(0),
    ])
}
