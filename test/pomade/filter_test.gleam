import pomade/internal/filter
import pomade/internal/scanner

pub fn empty_test() {
  assert [] == filter.filter([])
}

pub fn elide_set_delimiters_test() {
  assert [
      scanner.Text("random"),
      scanner.Whitespace(" "),
      scanner.Text("text"),
      scanner.Newline("\n"),
      scanner.Text("foo"),
      scanner.Newline("\n"),
    ]
    == filter.filter([
      scanner.Text("random"),
      scanner.Whitespace(" "),
      scanner.Text("text"),
      scanner.Newline("\n"),
      scanner.LeftDelimiter,
      scanner.SetDelimiters("<", ">"),
      scanner.RightDelimiter,
      scanner.Text("foo"),
      scanner.Newline("\n"),
    ])
}

pub fn elide_comment_test() {
  assert [
      scanner.Text("random"),
      scanner.Whitespace(" "),
      scanner.Text("text"),
      scanner.Newline("\n"),
      scanner.Text("foo"),
      scanner.Newline("\n"),
    ]
    == filter.filter([
      scanner.Text("random"),
      scanner.Whitespace(" "),
      scanner.Text("text"),
      scanner.Newline("\n"),
      scanner.LeftDelimiter,
      scanner.Comment,
      scanner.RightDelimiter,
      scanner.Text("foo"),
      scanner.Newline("\n"),
    ])
}

pub fn indented_standalone_test() {
  assert [
      scanner.Text("Begin."),
      scanner.Newline("\n"),
      scanner.Text("End."),
      scanner.Newline("\n"),
      scanner.Eof,
    ]
    == filter.filter([
      scanner.Text("Begin."),
      scanner.Newline("\n"),
      scanner.Whitespace("  "),
      scanner.LeftDelimiter,
      scanner.Comment,
      scanner.RightDelimiter,
      scanner.Newline("\n"),
      scanner.Text("End."),
      scanner.Newline("\n"),
      scanner.Eof,
    ])
}

pub fn standalone_without_newline_test() {
  assert [scanner.Text("!"), scanner.Newline("\n"), scanner.Eof]
    == filter.filter([
      scanner.Text("!"),
      scanner.Newline("\n"),
      scanner.Whitespace("  "),
      scanner.LeftDelimiter,
      scanner.Comment,
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn indented_inline_test() {
  let assert Ok(tokens) = scanner.scan("  12 {{! 34 }}\n")
  assert [
      scanner.Whitespace("  "),
      scanner.Text("12"),
      scanner.Whitespace(" "),
      scanner.LeftDelimiter,
      scanner.Comment,
      scanner.RightDelimiter,
      scanner.Newline("\n"),
      scanner.Eof,
    ]
    == tokens

  let ast = filter.filter(tokens)
  assert [
      scanner.Whitespace("  "),
      scanner.Text("12"),
      scanner.Whitespace(" "),
      scanner.Newline("\n"),
      scanner.Eof,
    ]
    == ast
}
