import pomade/internal/filter
import pomade/internal/scanner

pub fn empty_test() {
  assert [] == filter.filter([])
}

pub fn elide_set_delimiters_test() {
  assert [
      scanner.Text(0, "random"),
      scanner.Whitespace(0, " "),
      scanner.Text(0, "text"),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "foo"),
      scanner.Newline(0, "\n"),
    ]
    == filter.filter([
      scanner.Text(0, "random"),
      scanner.Whitespace(0, " "),
      scanner.Text(0, "text"),
      scanner.Newline(0, "\n"),
      scanner.SetDelimiters(0, "<", ">"),
      scanner.Text(0, "foo"),
      scanner.Newline(0, "\n"),
    ])
}

pub fn elide_comment_test() {
  assert [
      scanner.Text(0, "random"),
      scanner.Whitespace(0, " "),
      scanner.Text(0, "text"),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "foo"),
      scanner.Newline(0, "\n"),
    ]
    == filter.filter([
      scanner.Text(0, "random"),
      scanner.Whitespace(0, " "),
      scanner.Text(0, "text"),
      scanner.Newline(0, "\n"),
      scanner.Comment(0),
      scanner.Text(0, "foo"),
      scanner.Newline(0, "\n"),
    ])
}

pub fn indented_standalone_test() {
  assert [
      scanner.Text(0, "Begin."),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "End."),
      scanner.Newline(0, "\n"),
      scanner.Eof,
    ]
    == filter.filter([
      scanner.Text(0, "Begin."),
      scanner.Newline(0, "\n"),
      scanner.Whitespace(0, "  "),
      scanner.Comment(0),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "End."),
      scanner.Newline(0, "\n"),
      scanner.Eof,
    ])
}

pub fn standalone_without_newline_test() {
  assert [scanner.Text(0, "!"), scanner.Newline(0, "\n"), scanner.Eof]
    == filter.filter([
      scanner.Text(0, "!"),
      scanner.Newline(0, "\n"),
      scanner.Whitespace(0, "  "),
      scanner.Comment(0),
      scanner.Eof,
    ])
}

pub fn indented_inline_test() {
  let assert Ok(tokens) = scanner.scan("  12 {{! 34 }}\n")
  assert [
      scanner.Whitespace(1, "  "),
      scanner.Text(1, "12"),
      scanner.Whitespace(1, " "),
      scanner.Comment(1),
      scanner.Newline(1, "\n"),
      scanner.Eof,
    ]
    == tokens

  let ast = filter.filter(tokens)
  assert [
      scanner.Whitespace(1, "  "),
      scanner.Text(1, "12"),
      scanner.Whitespace(1, " "),
      scanner.Newline(1, "\n"),
      scanner.Eof,
    ]
    == ast
}
