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
      scanner.RawVariable(1),
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
      scanner.SectionStart(1),
      scanner.Identifier(6, "person"),
      scanner.RightDelimiter(2),
      scanner.LeftDelimiter(2),
      scanner.Identifier(4, "name"),
      scanner.RightDelimiter(2),
      scanner.LeftDelimiter(2),
      scanner.ClosingTag(1),
      scanner.Identifier(6, "person"),
      scanner.RightDelimiter(2),
    ])
}
