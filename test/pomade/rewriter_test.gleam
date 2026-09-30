import gleam/option.{None, Some}

import pomade/internal/rewriter
import pomade/internal/scanner

pub fn empty_test() {
  assert [] == rewriter.rewrite([], None)
}

pub fn elide_set_delimiters_test() {
  assert [
      scanner.Text(0, "random text"),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "foo"),
      scanner.Newline(0, "\n"),
    ]
    == rewriter.rewrite(
      [
        scanner.Text(0, "random"),
        scanner.Whitespace(0, " "),
        scanner.Text(0, "text"),
        scanner.Newline(0, "\n"),
        scanner.SetDelimiters(0, "<", ">"),
        scanner.Text(0, "foo"),
        scanner.Newline(0, "\n"),
      ],
      None,
    )
}

pub fn elide_comment_test() {
  assert [
      scanner.Text(0, "random text"),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "foo"),
      scanner.Newline(0, "\n"),
    ]
    == rewriter.rewrite(
      [
        scanner.Text(0, "random"),
        scanner.Whitespace(0, " "),
        scanner.Text(0, "text"),
        scanner.Newline(0, "\n"),
        scanner.Comment(0),
        scanner.Text(0, "foo"),
        scanner.Newline(0, "\n"),
      ],
      None,
    )
}

pub fn indented_standalone_test() {
  assert [
      scanner.Text(0, "Begin."),
      scanner.Newline(0, "\n"),
      scanner.Text(0, "End."),
      scanner.Newline(0, "\n"),
      scanner.Eof(0),
    ]
    == rewriter.rewrite(
      [
        scanner.Text(0, "Begin."),
        scanner.Newline(0, "\n"),
        scanner.Whitespace(0, "  "),
        scanner.Comment(0),
        scanner.Newline(0, "\n"),
        scanner.Text(0, "End."),
        scanner.Newline(0, "\n"),
        scanner.Eof(0),
      ],
      None,
    )
}

pub fn standalone_without_newline_test() {
  assert [scanner.Text(0, "!"), scanner.Newline(0, "\n"), scanner.Eof(0)]
    == rewriter.rewrite(
      [
        scanner.Text(0, "!"),
        scanner.Newline(0, "\n"),
        scanner.Whitespace(0, "  "),
        scanner.Comment(0),
        scanner.Eof(0),
      ],
      None,
    )
}

pub fn indented_inline_test() {
  let assert Ok(tokens) = scanner.scan("  12 {{! 34 }}\n")
  assert [
      scanner.Whitespace(1, "  "),
      scanner.Text(1, "12"),
      scanner.Whitespace(1, " "),
      scanner.Comment(1),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ]
    == tokens

  let ast = rewriter.rewrite(tokens, None)
  assert [
      scanner.Text(1, "  12 "),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ]
    == ast
}

pub fn indented_partial_test() {
  assert [
      scanner.Indentation(0, "  \t"),
      scanner.Partial(0, "hello"),
      scanner.Eof(0),
    ]
    == rewriter.rewrite(
      [
        scanner.Whitespace(0, "  \t"),
        scanner.Partial(0, "hello"),
        scanner.Newline(0, "\n"),
        scanner.Eof(0),
      ],
      None,
    )
}

pub fn indent_test() {
  assert [scanner.Text(0, "  \tfoo"), scanner.Eof(0)]
    == rewriter.rewrite(
      [
        scanner.Text(0, "foo"),
        scanner.Eof(0),
      ],
      Some("  \t"),
    )
}
