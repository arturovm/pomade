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
