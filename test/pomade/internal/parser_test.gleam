import pomade/internal/parser
import pomade/internal/scanner

pub fn empty_parser_test() {
  let assert Ok(parser.Template([])) = parser.parse([])
}

pub fn text_test() {
  let assert Ok(parser.Template([parser.Text("hello")])) =
    parser.parse([scanner.Text("hello")])
}

pub fn variable_test() {
  let assert Ok(parser.Template([parser.Variable(["hello"])])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.Identifier("hello"),
      scanner.RightDelimiter,
    ])
}

pub fn dotted_variable_test() {
  let assert Ok(parser.Template([parser.Variable(["hello", "world"])])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.Identifier("hello"),
      scanner.Dot,
      scanner.Identifier("world"),
      scanner.RightDelimiter,
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok(parser.Template([parser.Variable(["."])])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.Dot,
      scanner.RightDelimiter,
    ])
}

pub fn raw_variable_test() {
  let assert Ok(parser.Template([parser.RawVariable(["hello"])])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.RawVariableIndicator,
      scanner.Identifier("hello"),
      scanner.RightDelimiter,
    ])

  let assert Ok(parser.Template([parser.RawVariable(["goodbye"])])) =
    parser.parse([
      scanner.LeftTripleMustache,
      scanner.Identifier("goodbye"),
      scanner.RightTripleMustache,
    ])
}

pub fn section_test() {
  let assert Ok(parser.Template([
    parser.Section(["person"], [parser.Variable(["name"])]),
  ])) =
    parser.parse([
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
    ])
}

pub fn inverted_section_test() {
  let assert Ok(parser.Template([
    parser.InvertedSection(["person"], [parser.Text("no repos :(")]),
  ])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.InvertedSectionIndicator,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
      scanner.Text("no repos :("),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("person"),
      scanner.RightDelimiter,
    ])
}

pub fn partial_test() {
  let assert Ok(parser.Template([parser.Partial(["box"])])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.PartialIndicator,
      scanner.Identifier("box"),
      scanner.RightDelimiter,
    ])
}

pub fn block_test() {
  let assert Ok(parser.Template([
    parser.Block(["title"], [parser.Text("hello, world!")]),
  ])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.BlockIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.Text("hello, world!"),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
    ])
}

pub fn parent_test() {
  let assert Ok(parser.Template([
    parser.Parent(["title"], [parser.Text("foo, bar, baz")]),
  ])) =
    parser.parse([
      scanner.LeftDelimiter,
      scanner.ParentIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
      scanner.Text("foo, bar, baz"),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("title"),
      scanner.RightDelimiter,
    ])
}

pub fn elide_comments_test() {
  let assert Ok(parser.Template([parser.Text("Begin"), parser.Text("End")])) =
    parser.parse([
      scanner.Text("Begin"),
      scanner.Newline,
      scanner.Text("\t  "),
      scanner.Ignored,
      scanner.Newline,
      scanner.Text("End"),
    ])
}

pub fn recursion_test() {
  let assert Ok(parser.Template([
    parser.Text("some text"),
    parser.Section(
      ["a_section"],
      [
        parser.Variable(["some_variable"]),
        parser.InvertedSection(["inner_section"], [parser.Text("inner text")]),
      ],
    ),
  ])) =
    parser.parse([
      scanner.Text("some text"),
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
      scanner.Text("inner text"),
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("inner_section"),
      scanner.RightDelimiter,
      scanner.LeftDelimiter,
      scanner.ClosingIndicator,
      scanner.Identifier("a_section"),
      scanner.RightDelimiter,
    ])
}
