import pomade/internal/scanner

import pomade

pub fn empty_parser_test() {
  let assert Ok([]) = pomade.parse([scanner.Eof])
}

pub fn text_test() {
  let assert Ok([
    pomade.Text("hello,"),
    pomade.Whitespace(" "),
    pomade.Text("world!"),
  ]) =
    pomade.parse([
      scanner.TextLiteral("hello,"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("world!"),
      scanner.Eof,
    ])
}

pub fn variable_test() {
  let assert Ok([pomade.Variable(["hello"])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.Identifier("hello"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn dotted_variable_test() {
  let assert Ok([pomade.Variable(["hello", "world"])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.Identifier("hello"),
      scanner.Dot,
      scanner.Identifier("world"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok([pomade.Variable(["."])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.Dot,
      scanner.RightDelimiter,
      scanner.Eof,
    ])

  let assert Error(pomade.UnexpectedTokenError(scanner.Identifier("foo"))) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.Dot,
      scanner.Identifier("foo"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn raw_variable_test() {
  let assert Ok([pomade.RawVariable(["hello"])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.RawVariableIndicator,
      scanner.Identifier("hello"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])

  let assert Ok([pomade.RawVariable(["goodbye"])]) =
    pomade.parse([
      scanner.LeftTripleMustache,
      scanner.Identifier("goodbye"),
      scanner.RightTripleMustache,
      scanner.Eof,
    ])
}

pub fn section_test() {
  let assert Ok([pomade.Section(["person"], [pomade.Variable(["name"])])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.SectionIndicator,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.Identifier("name"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn inverted_section_test() {
  let assert Ok([
    pomade.InvertedSection(
      ["person"],
      [
        pomade.Text("no"),
        pomade.Whitespace(" "),
        pomade.Text("repos"),
        pomade.Whitespace(" "),
        pomade.Text(":("),
      ],
    ),
  ]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.InvertedSectionIndicator,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.TextLiteral("no"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("repos"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral(":("),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn partial_test() {
  let assert Ok([pomade.Partial(["box"])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.PartialIndicator,
      scanner.Identifier("box"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn block_test() {
  let assert Ok([pomade.Block(["title"], [pomade.Text("hello, world!")])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.BlockIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.TextLiteral("hello, world!"),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn parent_test() {
  let assert Ok([pomade.Parent(["title"], [pomade.Text("foo, bar, baz")])]) =
    pomade.parse([
      scanner.LeftDelimiter,
      scanner.ParentIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.TextLiteral("foo, bar, baz"),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn elide_comments_test() {
  let assert Ok([pomade.Text("Begin"), pomade.Newline("\n"), pomade.Text("End")]) =
    pomade.parse([
      scanner.TextLiteral("Begin"),
      scanner.NewlineLiteral("\n"),
      scanner.WhitespaceLiteral("\t  "),
      scanner.Ignored,
      scanner.NewlineLiteral("\n"),
      scanner.TextLiteral("End"),
      scanner.Eof,
    ])
}

pub fn recursion_test() {
  let assert Ok([
    pomade.Text("some text"),
    pomade.Section(
      ["a_section"],
      [
        pomade.Variable(["some_variable"]),
        pomade.InvertedSection(["inner_section"], [pomade.Text("inner text")]),
      ],
    ),
  ]) =
    pomade.parse([
      scanner.TextLiteral("some text"),
      scanner.LeftDelimiter,
      scanner.SectionIndicator,
      scanner.Identifier("a_section"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.Identifier("some_variable"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.InvertedSectionIndicator,
      scanner.Identifier("inner_section"),
      scanner.RightDelimiter,
      scanner.TextLiteral("inner text"),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("inner_section"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("a_section"),
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}
