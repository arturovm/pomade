import gleam/option.{None, Some}

import pomade/internal/rewriter
import pomade/internal/scanner

pub fn empty_test() {
  assert [] == rewriter.rewrite([])
  assert [rewriter.Eof(1)] == rewriter.rewrite([scanner.Eof(1)])
}

pub fn standalone_interpolation_test() {
  assert [
      rewriter.Indent(1),
      rewriter.Leading(1, "  "),
      rewriter.Variable(1, ["string"]),
      rewriter.Literal(1, "\n"),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, "  "),
      scanner.Variable(1, ["string"]),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ])
}

pub fn elide_set_delimiters_test() {
  assert [
      rewriter.Indent(0),
      rewriter.Literal(0, "random text\n"),
      rewriter.Indent(0),
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
      rewriter.Indent(0),
      rewriter.Literal(0, "random text\n"),
      rewriter.Indent(0),
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
      rewriter.Indent(0),
      rewriter.Literal(0, "Begin.\n"),
      rewriter.Indent(0),
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
      rewriter.Indent(0),
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
      scanner.Whitespace(1, "  "),
      scanner.Text(1, "12 "),
      scanner.Comment(1),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ]
    == tokens

  let ast = rewriter.rewrite(tokens)
  assert [
      rewriter.Indent(1),
      rewriter.Leading(1, "  "),
      rewriter.Literal(1, "12 \n"),
      rewriter.Eof(2),
    ]
    == ast
}

pub fn line_start_test() {
  assert [rewriter.Indent(1), rewriter.Literal(1, "\n"), rewriter.Eof(2)]
    == rewriter.rewrite([scanner.Newline(1, "\n"), scanner.Eof(2)])
}

pub fn standalone_partial_test() {
  // leading whitespace
  assert [
      rewriter.Partial(1, scanner.StaticName("hello"), Some(" \t")),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.Partial(1, scanner.StaticName("hello")),
      scanner.Newline(1, " \n"),
      scanner.Eof(2),
    ])

  assert [
      rewriter.Partial(1, scanner.StaticName("hello"), Some(" \t")),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.Partial(1, scanner.StaticName("hello")),
      scanner.Eof(1),
    ])
  // trailing whitespace
  assert [
      rewriter.Partial(1, scanner.StaticName("hello"), Some(" \t")),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.Partial(1, scanner.StaticName("hello")),
      scanner.Whitespace(1, "  "),
      scanner.Newline(1, " \n"),
      scanner.Eof(2),
    ])

  assert [
      rewriter.Partial(1, scanner.StaticName("hello"), Some(" \t")),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.Partial(1, scanner.StaticName("hello")),
      scanner.Whitespace(1, "  "),
      scanner.Eof(1),
    ])
}

pub fn standalone_block_test() {
  // leading whitespace
  assert [
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(Some(" \n")),
          ),
        ),
      ),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.BlockStart(1, "hello"),
      scanner.Newline(1, " \n"),
      scanner.Eof(2),
    ])

  assert [
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(None),
          ),
        ),
      ),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.BlockStart(1, "hello"),
      scanner.Eof(1),
    ])
  // trailing whitespace
  assert [
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(Some("   \n")),
          ),
        ),
      ),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.BlockStart(1, "hello"),
      scanner.Whitespace(1, "  "),
      scanner.Newline(1, " \n"),
      scanner.Eof(2),
    ])

  assert [
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(Some("  ")),
          ),
        ),
      ),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.BlockStart(1, "hello"),
      scanner.Whitespace(1, "  "),
      scanner.Eof(1),
    ])
}

pub fn standalone_parent_test() {
  // leading whitespace
  assert [
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(Some(" \n")),
          ),
        ),
      ),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.ParentStart(1, "hello"),
      scanner.Newline(1, " \n"),
      scanner.Eof(2),
    ])

  assert [
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(None),
          ),
        ),
      ),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.ParentStart(1, "hello"),
      scanner.Eof(1),
    ])
  // trailing whitespace
  assert [
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(Some("   \n")),
          ),
        ),
      ),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.ParentStart(1, "hello"),
      scanner.Whitespace(1, "  "),
      scanner.Newline(1, " \n"),
      scanner.Eof(2),
    ])

  assert [
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(
            rewriter.Clears(Some(" \t")),
            rewriter.Clears(Some("  ")),
          ),
        ),
      ),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.Whitespace(1, " \t"),
      scanner.ParentStart(1, "hello"),
      scanner.Whitespace(1, "  "),
      scanner.Eof(1),
    ])
}

pub fn block_clerance_test() {
  // clears both
  assert [
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.Clears(Some("\n"))),
        ),
      ),
    ]
    == rewriter.rewrite([
      scanner.BlockStart(1, "hello"),
      scanner.Newline(1, "\n"),
    ])
  assert [
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.Clears(None)),
        ),
      ),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.BlockStart(1, "hello"),
      scanner.Eof(1),
    ])
  // clears start
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a\n"),
      rewriter.Indent(2),
      rewriter.BlockStart(
        2,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
        ),
      ),
      rewriter.Literal(2, " b\n"),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a"),
      scanner.Newline(1, "\n"),
      scanner.BlockStart(2, "hello"),
      scanner.Text(2, " b"),
      scanner.Newline(2, "\n"),
    ])
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a\n"),
      rewriter.Indent(2),
      rewriter.BlockStart(
        2,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
        ),
      ),
      rewriter.Literal(2, " b\n"),
      rewriter.Eof(3),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a"),
      scanner.Newline(1, "\n"),
      scanner.BlockStart(2, "hello"),
      scanner.Text(2, " b"),
      scanner.Newline(2, "\n"),
      scanner.Eof(3),
    ])
  // clears end
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.Indent(2),
      rewriter.Literal(2, "b\n"),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.BlockStart(1, "hello"),
      scanner.Newline(1, "\n"),
      scanner.Text(2, "b"),
      scanner.Newline(2, "\n"),
    ])
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.Indent(2),
      rewriter.Literal(2, "b\n"),
      rewriter.Eof(3),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.BlockStart(1, "hello"),
      scanner.Newline(1, "\n"),
      scanner.Text(2, "b"),
      scanner.Newline(2, "\n"),
      scanner.Eof(3),
    ])
  // clears none
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, " b\n"),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.BlockStart(1, "hello"),
      scanner.Text(1, " b"),
      scanner.Newline(1, "\n"),
    ])
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, " b\n"),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.BlockStart(1, "hello"),
      scanner.Text(1, " b"),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ])
}

pub fn parent_clerance_test() {
  // clears both
  assert [
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.Clears(Some("\n"))),
        ),
      ),
    ]
    == rewriter.rewrite([
      scanner.ParentStart(1, "hello"),
      scanner.Newline(1, "\n"),
    ])
  assert [
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.Clears(None)),
        ),
      ),
      rewriter.Eof(1),
    ]
    == rewriter.rewrite([
      scanner.ParentStart(1, "hello"),
      scanner.Eof(1),
    ])
  // clears start
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a\n"),
      rewriter.Indent(2),
      rewriter.ParentStart(
        2,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
        ),
      ),
      rewriter.Literal(2, " b\n"),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a"),
      scanner.Newline(1, "\n"),
      scanner.ParentStart(2, "hello"),
      scanner.Text(2, " b"),
      scanner.Newline(2, "\n"),
    ])
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a\n"),
      rewriter.Indent(2),
      rewriter.ParentStart(
        2,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
        ),
      ),
      rewriter.Literal(2, " b\n"),
      rewriter.Eof(3),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a"),
      scanner.Newline(1, "\n"),
      scanner.ParentStart(2, "hello"),
      scanner.Text(2, " b"),
      scanner.Newline(2, "\n"),
      scanner.Eof(3),
    ])
  // clears end
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.Indent(2),
      rewriter.Literal(2, "b\n"),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.ParentStart(1, "hello"),
      scanner.Newline(1, "\n"),
      scanner.Text(2, "b"),
      scanner.Newline(2, "\n"),
    ])
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.Indent(2),
      rewriter.Literal(2, "b\n"),
      rewriter.Eof(3),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.ParentStart(1, "hello"),
      scanner.Newline(1, "\n"),
      scanner.Text(2, "b"),
      scanner.Newline(2, "\n"),
      scanner.Eof(3),
    ])
  // clears none
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, " b\n"),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.ParentStart(1, "hello"),
      scanner.Text(1, " b"),
      scanner.Newline(1, "\n"),
    ])
  assert [
      rewriter.Indent(1),
      rewriter.Literal(1, "a "),
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "hello",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, " b\n"),
      rewriter.Eof(2),
    ]
    == rewriter.rewrite([
      scanner.Text(1, "a "),
      scanner.ParentStart(1, "hello"),
      scanner.Text(1, " b"),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ])
}
