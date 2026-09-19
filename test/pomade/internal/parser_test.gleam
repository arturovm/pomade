import pomade

pub fn empty_parser_test() {
  let assert Ok([]) = pomade.parse([pomade.Eof])
}

pub fn text_test() {
  let assert Ok([pomade.Text("hello")]) =
    pomade.parse([pomade.TextLiteral("hello"), pomade.Eof])
}

pub fn variable_test() {
  let assert Ok([pomade.Variable(["hello"])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.Identifier("hello"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn dotted_variable_test() {
  let assert Ok([pomade.Variable(["hello", "world"])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.Identifier("hello"),
      pomade.Dot,
      pomade.Identifier("world"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok([pomade.Variable(["."])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.Dot,
      pomade.RightDelimiter,
      pomade.Eof,
    ])

  let assert Error(pomade.UnexpectedTokenError(pomade.Identifier("foo"))) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.Dot,
      pomade.Identifier("foo"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn raw_variable_test() {
  let assert Ok([pomade.RawVariable(["hello"])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.RawVariableIndicator,
      pomade.Identifier("hello"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])

  let assert Ok([pomade.RawVariable(["goodbye"])]) =
    pomade.parse([
      pomade.LeftTripleMustache,
      pomade.Identifier("goodbye"),
      pomade.RightTripleMustache,
      pomade.Eof,
    ])
}

pub fn section_test() {
  let assert Ok([pomade.Section(["person"], [pomade.Variable(["name"])])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.SectionIndicator,
      pomade.Identifier("person"),
      pomade.RightDelimiter,
      pomade.LeftDelimiter,
      pomade.Identifier("name"),
      pomade.RightDelimiter,
      pomade.LeftDelimiter,
      pomade.ClosingIndicator,
      pomade.Identifier("person"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn inverted_section_test() {
  let assert Ok([
    pomade.InvertedSection(["person"], [pomade.Text("no repos :(")]),
  ]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.InvertedSectionIndicator,
      pomade.Identifier("person"),
      pomade.RightDelimiter,
      pomade.TextLiteral("no repos :("),
      pomade.LeftDelimiter,
      pomade.ClosingIndicator,
      pomade.Identifier("person"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn partial_test() {
  let assert Ok([pomade.Partial(["box"])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.PartialIndicator,
      pomade.Identifier("box"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn block_test() {
  let assert Ok([pomade.Block(["title"], [pomade.Text("hello, world!")])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.BlockIndicator,
      pomade.Identifier("title"),
      pomade.RightDelimiter,
      pomade.TextLiteral("hello, world!"),
      pomade.LeftDelimiter,
      pomade.ClosingIndicator,
      pomade.Identifier("title"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn parent_test() {
  let assert Ok([pomade.Parent(["title"], [pomade.Text("foo, bar, baz")])]) =
    pomade.parse([
      pomade.LeftDelimiter,
      pomade.ParentIndicator,
      pomade.Identifier("title"),
      pomade.RightDelimiter,
      pomade.TextLiteral("foo, bar, baz"),
      pomade.LeftDelimiter,
      pomade.ClosingIndicator,
      pomade.Identifier("title"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}

pub fn elide_comments_test() {
  let assert Ok([pomade.Text("Begin"), pomade.Newline("\n"), pomade.Text("End")]) =
    pomade.parse([
      pomade.TextLiteral("Begin"),
      pomade.NewlineLiteral("\n"),
      pomade.TextLiteral("\t  "),
      pomade.Ignored,
      pomade.NewlineLiteral("\n"),
      pomade.TextLiteral("End"),
      pomade.Eof,
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
      pomade.TextLiteral("some text"),
      pomade.LeftDelimiter,
      pomade.SectionIndicator,
      pomade.Identifier("a_section"),
      pomade.RightDelimiter,
      pomade.LeftDelimiter,
      pomade.Identifier("some_variable"),
      pomade.RightDelimiter,
      pomade.LeftDelimiter,
      pomade.InvertedSectionIndicator,
      pomade.Identifier("inner_section"),
      pomade.RightDelimiter,
      pomade.TextLiteral("inner text"),
      pomade.LeftDelimiter,
      pomade.ClosingIndicator,
      pomade.Identifier("inner_section"),
      pomade.RightDelimiter,
      pomade.LeftDelimiter,
      pomade.ClosingIndicator,
      pomade.Identifier("a_section"),
      pomade.RightDelimiter,
      pomade.Eof,
    ])
}
