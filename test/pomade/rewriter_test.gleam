import gleam/option.{None, Some}

import pomade/internal/rewriter
import pomade/internal/scanner

pub fn empty_test() {
  assert [] == rewriter.rewrite([], None)
  assert [rewriter.Eof(1)] == rewriter.rewrite([scanner.Eof(1)], None)
}

pub fn elide_set_delimiters_test() {
  assert [
      rewriter.LineStart(0),
      rewriter.Literal(0, "random text\n"),
      rewriter.LineStart(0),
      rewriter.Literal(0, "foo\n"),
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
      rewriter.LineStart(0),
      rewriter.Literal(0, "random text\n"),
      rewriter.LineStart(0),
      rewriter.Literal(0, "foo\n"),
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
      rewriter.LineStart(0),
      rewriter.Literal(0, "Begin.\n"),
      rewriter.LineStart(0),
      rewriter.Literal(0, "End.\n"),
      rewriter.Eof(0),
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
  assert [
      rewriter.LineStart(0),
      rewriter.Literal(0, "!\n"),
      rewriter.Eof(0),
    ]
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
      scanner.Text(1, "  12 "),
      scanner.Comment(1),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ]
    == tokens

  let ast = rewriter.rewrite(tokens, None)
  assert [
      rewriter.LineStart(1),
      rewriter.Literal(1, "  12 \n"),
      rewriter.Eof(2),
    ]
    == ast
}

pub fn indented_partial_test() {
  assert [
      rewriter.LineStart(0),
      rewriter.Indentation(0, "  \t"),
      rewriter.Partial(0, scanner.StaticName("hello")),
      rewriter.Eof(0),
    ]
    == rewriter.rewrite(
      [
        scanner.Whitespace(0, "  \t"),
        scanner.Partial(0, scanner.StaticName("hello")),
        scanner.Newline(0, "\n"),
        scanner.Eof(0),
      ],
      None,
    )
}

pub fn indent_test() {
  assert [
      rewriter.LineStart(1),
      rewriter.Literal(1, "  \tfoo\n"),
      rewriter.LineStart(2),
      rewriter.Literal(2, "  \tbar\n"),
      rewriter.Eof(3),
    ]
    == rewriter.rewrite(
      [
        scanner.Text(1, "foo"),
        scanner.Newline(1, "\n"),
        scanner.Text(2, "bar"),
        scanner.Newline(2, "\n"),
        scanner.Eof(3),
      ],
      Some("  \t"),
    )
}

pub fn line_start_test() {
  assert [rewriter.LineStart(1), rewriter.Literal(1, "\n"), rewriter.Eof(2)]
    == rewriter.rewrite([scanner.Newline(1, "\n"), scanner.Eof(2)], None)
}
