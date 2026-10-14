import pomade/internal/rewriter
import pomade/internal/scanner

pub fn empty_test() {
  assert [] == rewriter.rewrite([])
  assert [rewriter.Eof(1)] == rewriter.rewrite([scanner.Eof(1)])
}

pub fn elide_set_delimiters_test() {
  assert [
      rewriter.LineStart(0),
      rewriter.Literal(0, "random text\n"),
      rewriter.LineStart(0),
      rewriter.Literal(0, "foo\n"),
    ]
    == rewriter.rewrite([
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
      rewriter.LineStart(0),
      rewriter.Literal(0, "random text\n"),
      rewriter.LineStart(0),
      rewriter.Literal(0, "foo\n"),
    ]
    == rewriter.rewrite([
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
      rewriter.LineStart(0),
      rewriter.Literal(0, "Begin.\n"),
      rewriter.LineStart(0),
      rewriter.Literal(0, "End.\n"),
      rewriter.Eof(0),
    ]
    == rewriter.rewrite([
      scanner.Text(0, "Begin."),
      scanner.Newline(0, "\n"),
      scanner.Whitespace(0, "  "),
      scanner.Comment(0),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "End."),
      scanner.Newline(0, "\n"),
      scanner.Eof(0),
    ])
}

pub fn standalone_without_newline_test() {
  assert [
      rewriter.LineStart(0),
      rewriter.Literal(0, "!\n"),
      rewriter.Eof(0),
    ]
    == rewriter.rewrite([
      scanner.Text(0, "!"),
      scanner.Newline(0, "\n"),
      scanner.Whitespace(0, "  "),
      scanner.Comment(0),
      scanner.Eof(0),
    ])
}

pub fn indented_inline_test() {
  let assert Ok(tokens) = scanner.scan("  12 {{! 34 }}\n")
  assert [
      scanner.Text(1, "  12 "),
      scanner.Comment(1),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ]
    == tokens

  let ast = rewriter.rewrite(tokens)
  assert [
      rewriter.LineStart(1),
      rewriter.Literal(1, "  12 \n"),
      rewriter.Eof(2),
    ]
    == ast
}

pub fn line_start_test() {
  assert [rewriter.LineStart(1), rewriter.Literal(1, "\n"), rewriter.Eof(2)]
    == rewriter.rewrite([scanner.Newline(1, "\n"), scanner.Eof(2)])
}
