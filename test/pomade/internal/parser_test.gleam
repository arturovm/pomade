import pomade/internal/parser
import pomade/internal/scanner

pub fn empty_parser_test() {
  let assert Ok(parser.Template([])) = parser.parse([])
}

pub fn text_test() {
  let assert Ok(parser.Template([parser.Text("hello")])) =
    parser.parse([scanner.Text(5, "hello")])
}

pub fn variable_test() {
  let assert Ok(parser.Template([parser.Variable(["hello"])])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.Identifier(5, "hello"),
      scanner.RightDelimiter(2),
    ])
}

pub fn dotted_variable_test() {
  let assert Ok(parser.Template([parser.Variable(["hello", "world"])])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.Identifier(5, "hello"),
      scanner.Dot(5),
      scanner.Identifier(5, "world"),
      scanner.RightDelimiter(2),
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok(parser.Template([parser.Variable(["."])])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.Dot(5),
      scanner.RightDelimiter(2),
    ])
}

pub fn raw_variable_test() {
  let assert Ok(parser.Template([parser.RawVariable(["hello"])])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.RawVariableIndicator(1),
      scanner.Identifier(5, "hello"),
      scanner.RightDelimiter(2),
    ])

  let assert Ok(parser.Template([parser.RawVariable(["goodbye"])])) =
    parser.parse([
      scanner.LeftTripleMustache(3),
      scanner.Identifier(5, "goodbye"),
      scanner.RightTripleMustache(3),
    ])
}

pub fn section_test() {
  let assert Ok(parser.Template([
    parser.Section(["person"], [parser.Variable(["name"])]),
  ])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.SectionIndicator(1),
      scanner.Identifier(6, "person"),
      scanner.RightDelimiter(2),
      scanner.LeftDelimiter(2),
      scanner.Identifier(4, "name"),
      scanner.RightDelimiter(2),
      scanner.LeftDelimiter(2),
      scanner.ClosingIndicator(1),
      scanner.Identifier(6, "person"),
      scanner.RightDelimiter(2),
    ])
}

pub fn inverted_section_test() {
  let assert Ok(parser.Template([
    parser.InvertedSection(["person"], [parser.Text("no repos :(")]),
  ])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.InvertedSectionIndicator(1),
      scanner.Identifier(6, "person"),
      scanner.RightDelimiter(2),
      scanner.Text(11, "no repos :("),
      scanner.LeftDelimiter(2),
      scanner.ClosingIndicator(1),
      scanner.Identifier(6, "person"),
      scanner.RightDelimiter(2),
    ])
}

pub fn partial_test() {
  let assert Ok(parser.Template([parser.Partial(["box"])])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.PartialIndicator(1),
      scanner.Identifier(6, "box"),
      scanner.RightDelimiter(2),
    ])
}

pub fn block_test() {
  let assert Ok(parser.Template([
    parser.Block(["title"], [parser.Text("hello, world!")]),
  ])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.BlockIndicator(1),
      scanner.Identifier(6, "title"),
      scanner.RightDelimiter(2),
      scanner.Text(11, "hello, world!"),
      scanner.LeftDelimiter(2),
      scanner.ClosingIndicator(1),
      scanner.Identifier(6, "title"),
      scanner.RightDelimiter(2),
    ])
}

pub fn parent_test() {
  let assert Ok(parser.Template([
    parser.Parent(["title"], [parser.Text("foo, bar, baz")]),
  ])) =
    parser.parse([
      scanner.LeftDelimiter(2),
      scanner.ParentIndicator(1),
      scanner.Identifier(6, "title"),
      scanner.RightDelimiter(2),
      scanner.Text(11, "foo, bar, baz"),
      scanner.LeftDelimiter(2),
      scanner.ClosingIndicator(1),
      scanner.Identifier(6, "title"),
      scanner.RightDelimiter(2),
    ])
}
