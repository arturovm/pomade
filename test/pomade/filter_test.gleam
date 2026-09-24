import pomade/internal/filter
import pomade/internal/scanner

pub fn empty_test() {
  assert [] == filter.filter([])
}

pub fn elide_set_delimiters_test() {
  assert [
      scanner.TextLiteral("random"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("text"),
      scanner.NewlineLiteral("\n"),
      scanner.TextLiteral("foo"),
      scanner.NewlineLiteral("\n"),
    ]
    == filter.filter([
      scanner.TextLiteral("random"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("text"),
      scanner.NewlineLiteral("\n"),
      scanner.LeftDelimiter,
      scanner.SetDelimiters("<", ">"),
      scanner.RightDelimiter,
      scanner.TextLiteral("foo"),
      scanner.NewlineLiteral("\n"),
    ])
}

pub fn elide_comment_test() {
  assert [
      scanner.TextLiteral("random"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("text"),
      scanner.NewlineLiteral("\n"),
      scanner.TextLiteral("foo"),
      scanner.NewlineLiteral("\n"),
    ]
    == filter.filter([
      scanner.TextLiteral("random"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("text"),
      scanner.NewlineLiteral("\n"),
      scanner.LeftDelimiter,
      scanner.Ignored,
      scanner.RightDelimiter,
      scanner.TextLiteral("foo"),
      scanner.NewlineLiteral("\n"),
    ])
}

pub fn indented_standalone_test() {
  assert [
      scanner.TextLiteral("Begin."),
      scanner.NewlineLiteral("\n"),
      scanner.TextLiteral("End."),
      scanner.NewlineLiteral("\n"),
      scanner.Eof,
    ]
    == filter.filter([
      scanner.TextLiteral("Begin."),
      scanner.NewlineLiteral("\n"),
      scanner.WhitespaceLiteral("  "),
      scanner.LeftDelimiter,
      scanner.Ignored,
      scanner.RightDelimiter,
      scanner.NewlineLiteral("\n"),
      scanner.TextLiteral("End."),
      scanner.NewlineLiteral("\n"),
      scanner.Eof,
    ])
}

pub fn standalone_without_newline_test() {
  assert [scanner.TextLiteral("!"), scanner.NewlineLiteral("\n"), scanner.Eof]
    == filter.filter([
      scanner.TextLiteral("!"),
      scanner.NewlineLiteral("\n"),
      scanner.WhitespaceLiteral("  "),
      scanner.LeftDelimiter,
      scanner.Ignored,
      scanner.RightDelimiter,
      scanner.Eof,
    ])
}

pub fn indented_inline_test() {
  let assert Ok(tokens) = scanner.scan("  12 {{! 34 }}\n")
  assert [
      scanner.WhitespaceLiteral("  "),
      scanner.TextLiteral("12"),
      scanner.WhitespaceLiteral(" "),
      scanner.LeftDelimiter,
      scanner.Ignored,
      scanner.RightDelimiter,
      scanner.NewlineLiteral("\n"),
      scanner.Eof,
    ]
    == tokens

  let ast = filter.filter(tokens)
  assert [
      scanner.WhitespaceLiteral("  "),
      scanner.TextLiteral("12"),
      scanner.WhitespaceLiteral(" "),
      scanner.NewlineLiteral("\n"),
      scanner.Eof,
    ]
    == ast
}
