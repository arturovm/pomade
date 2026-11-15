import gleam/option.{None, Some}

import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner

pub fn empty_parser_test() {
  assert Ok([]) == parser.parse([rewriter.Eof(0)])
}

pub fn indent_test() {
  assert Ok([parser.LineStart(None), parser.Literal("Hello")])
    == parser.parse([
      rewriter.LineStart(0, None),
      rewriter.Literal(0, "Hello"),
      rewriter.Eof(0),
    ])
}

pub fn line_start_test() {
  assert Ok([parser.LineStart(None)])
    == parser.parse([rewriter.LineStart(0, None), rewriter.Eof(0)])
}

pub fn text_test() {
  let assert Ok([parser.Literal("hello, world!")]) =
    parser.parse([
      rewriter.Literal(0, "hello, world!"),
      rewriter.Eof(0),
    ])
}

pub fn variable_test() {
  let assert Ok([parser.Variable(["hello"])]) =
    parser.parse([
      rewriter.Variable(0, ["hello"]),
      rewriter.Eof(0),
    ])
}

pub fn dotted_variable_test() {
  let assert Ok([parser.Variable(["hello", "world"])]) =
    parser.parse([
      rewriter.Variable(0, ["hello", "world"]),
      rewriter.Eof(0),
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok([parser.Variable(["."])]) =
    parser.parse([
      rewriter.Variable(0, ["."]),
      rewriter.Eof(0),
    ])
}

pub fn raw_variable_test() {
  let assert Ok([parser.RawVariable(["hello"])]) =
    parser.parse([
      rewriter.RawVariable(0, ["hello"]),
      rewriter.Eof(0),
    ])
}

pub fn section_test() {
  assert Ok([
      parser.Section(["person"], [parser.Variable(["name"])]),
    ])
    == parser.parse([
      rewriter.SectionStart(0, ["person"]),
      rewriter.Variable(0, ["name"]),
      rewriter.End(
        0,
        ["person"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.Eof(0),
    ])
}

pub fn inverted_section_test() {
  assert Ok([
      parser.InvertedSection(["person"], [parser.Literal("no repos :(")]),
    ])
    == parser.parse([
      rewriter.InvertedSectionStart(0, ["person"]),
      rewriter.Literal(0, "no repos :("),
      rewriter.End(
        0,
        ["person"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.Eof(0),
    ])
}

pub fn block_test() {
  assert Ok([
      parser.InlineParameter("title", [
        parser.Literal("hello :)"),
      ]),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "title",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, "hello :)"),
      rewriter.End(
        1,
        ["title"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.Eof(1),
    ])
}

pub fn parent_test() {
  assert Ok([
      parser.InlineParent("article", [
        parser.Argument("title", [
          parser.Literal("goodbye :("),
        ]),
      ]),
    ])
    == parser.parse([
      rewriter.ParentStart(
        0,
        rewriter.StartTagData(
          "article",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(0, "hello :)"),
      rewriter.BlockStart(
        0,
        rewriter.StartTagData(
          "title",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(0, "goodbye :("),
      rewriter.End(
        0,
        ["title"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.End(
        0,
        ["article"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.Eof(0),
    ])
}

pub fn partial_test() {
  let assert Ok([parser.Partial(scanner.StaticName("box"), None)]) =
    parser.parse([
      rewriter.Partial(0, scanner.StaticName("box"), None),
      rewriter.Eof(0),
    ])

  let assert Ok([parser.Partial(scanner.StaticName("box"), Some("  \t"))]) =
    parser.parse([
      rewriter.Partial(0, scanner.StaticName("box"), Some("  \t")),
      rewriter.Eof(0),
    ])

  let assert Ok([parser.InlinePartial(scanner.StaticName("box"))]) =
    parser.parse([
      rewriter.InlinePartial(0, scanner.StaticName("box")),
      rewriter.Eof(0),
    ])
}

pub fn recursion_test() {
  assert Ok([
      parser.Literal("some text"),
      parser.Section(["a_section"], [
        parser.Variable(["some_variable"]),
        parser.InvertedSection(["inner_section"], [parser.Literal("inner text")]),
      ]),
    ])
    == parser.parse([
      rewriter.Literal(0, "some text"),
      rewriter.SectionStart(0, ["a_section"]),
      rewriter.Variable(0, ["some_variable"]),
      rewriter.InvertedSectionStart(0, ["inner_section"]),
      rewriter.Literal(0, "inner text"),
      rewriter.End(
        0,
        ["inner_section"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.End(
        0,
        ["a_section"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.Eof(0),
    ])
}

pub fn standalone_parent_test() {
  assert Ok([
      parser.Parent("parent", Some("  "), [
        parser.Argument("block", []),
      ]),
    ])
    == parser.parse([
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "parent",
          rewriter.Clearance(rewriter.Clears(Some("  ")), rewriter.NotClears),
        ),
      ),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.End(
        2,
        ["block"],
        rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
      ),
      rewriter.End(
        2,
        ["parent"],
        rewriter.Clearance(rewriter.NotClears, rewriter.Clears(None)),
      ),
      rewriter.Eof(2),
    ])
}

pub fn standalone_parameter_test() {
  assert Ok([
      parser.Parameter("block", None, []),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
        ),
      ),
      rewriter.End(
        1,
        ["block"],
        rewriter.Clearance(rewriter.NotClears, rewriter.Clears(None)),
      ),
      rewriter.Eof(1),
    ])

  assert Ok([
      parser.Parameter("block", Some("    "), []),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(
            rewriter.Clears(Some("    ")),
            rewriter.Clears(Some("\n")),
          ),
        ),
      ),
      rewriter.End(
        1,
        ["block"],
        rewriter.Clearance(rewriter.Clears(Some("    ")), rewriter.Clears(None)),
      ),
      rewriter.Eof(1),
    ])
}

pub fn intrinsic_indentation_test() {
  assert Ok([
      parser.Parameter("block", Some("    "), [
        parser.LineStart(None),
        parser.Literal("content\n"),
      ]),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.Clears(None), rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.LineStart(2, Some("    ")),
      rewriter.Literal(2, "content\n"),
      rewriter.End(
        3,
        ["block"],
        rewriter.Clearance(rewriter.Clears(None), rewriter.Clears(None)),
      ),
      rewriter.Eof(3),
    ])

  assert Ok([
      parser.Parameter("block", Some("    "), [
        parser.LineStart(None),
        parser.Literal("content"),
      ]),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.Clears(None), rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.LineStart(2, Some("    ")),
      rewriter.Literal(2, "content"),
      rewriter.End(
        2,
        ["block"],
        rewriter.Clearance(rewriter.NotClears, rewriter.Clears(None)),
      ),
      rewriter.Eof(2),
    ])

  assert Ok([
      parser.Parent("parent", None, [
        parser.Argument("block", [
          parser.LineStart(None),
          parser.Literal("content\n"),
        ]),
      ]),
    ])
    == parser.parse([
      rewriter.ParentStart(
        1,
        rewriter.StartTagData(
          "parent",
          rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
        ),
      ),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
        ),
      ),
      rewriter.LineStart(2, Some("    ")),
      rewriter.Literal(2, "content\n"),
      rewriter.End(
        3,
        ["block"],
        rewriter.Clearance(rewriter.Clears(None), rewriter.NotClears),
      ),
      rewriter.End(
        3,
        ["parent"],
        rewriter.Clearance(rewriter.NotClears, rewriter.Clears(None)),
      ),
      rewriter.Eof(3),
    ])
}

pub fn deindentation_test() {
  assert Ok([
      parser.Parameter("block", Some("        "), [
        parser.LineStart(None),
        parser.Literal("text\n"),
        parser.LineStart(None),
        parser.Section(["section"], [
          parser.Literal("\n"),
          parser.LineStart(Some("    ")),
          parser.Literal("text\n"),
        ]),
      ]),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(
            rewriter.Clears(Some("    ")),
            rewriter.Clears(Some("\n")),
          ),
        ),
      ),
      rewriter.LineStart(2, Some("        ")),
      rewriter.Literal(2, "text\n"),
      rewriter.LineStart(3, Some("        ")),
      rewriter.SectionStart(3, ["section"]),
      rewriter.Literal(3, "\n"),
      rewriter.LineStart(4, Some("            ")),
      rewriter.Literal(4, "text\n"),
      rewriter.End(
        5,
        ["section"],
        rewriter.Clearance(
          rewriter.Clears(Some("        ")),
          rewriter.Clears(Some("\n")),
        ),
      ),
      rewriter.End(
        5,
        ["block"],
        rewriter.Clearance(rewriter.Clears(Some("    ")), rewriter.Clears(None)),
      ),
      rewriter.Eof(2),
    ])
}

pub fn surrounding_whitespace_test() {
  // standalone parameters always map to plain parameters
  assert Ok([
      parser.Parameter("block", Some(" "), [
        parser.Literal("  foo\n"),
        parser.LineStart(Some("   ")),
        parser.Literal("bar\n"),
      ]),
      parser.LineStart(None),
      parser.Literal("baz"),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.Clears(Some(" ")), rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, "  foo\n"),
      rewriter.LineStart(2, Some("   ")),
      rewriter.Literal(2, "bar\n"),
      rewriter.End(
        3,
        ["block"],
        rewriter.Clearance(
          rewriter.Clears(Some("    ")),
          rewriter.Clears(Some("\n")),
        ),
      ),
      rewriter.LineStart(4, None),
      rewriter.Literal(4, "baz"),
      rewriter.Eof(4),
    ])
  // inline parameters map to either an inline parameter or a plain parameter,
  // depending on the end clearance of the start tag
  // start tag is standalone
  assert Ok([
      parser.Parameter("block", None, [
        parser.LineStart(None),
        parser.Literal("  "),
      ]),
      parser.Literal(" foo"),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(
            rewriter.Clears(Some("  ")),
            rewriter.Clears(Some("  \n")),
          ),
        ),
      ),
      rewriter.LineStart(2, None),
      rewriter.End(
        2,
        ["block"],
        rewriter.Clearance(rewriter.Clears(Some("  ")), rewriter.NotClears),
      ),
      rewriter.Literal(2, " foo"),
      rewriter.Eof(3),
    ])

  // end tag is standalone
  assert Ok([
      parser.LineStart(None),
      parser.Literal("foo "),
      parser.InlineParameter("block", [
        parser.Literal("  \n"),
      ]),
    ])
    == parser.parse([
      rewriter.LineStart(1, None),
      rewriter.Literal(1, "foo "),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("  \n"))),
        ),
      ),
      rewriter.End(
        2,
        ["block"],
        rewriter.Clearance(
          rewriter.Clears(Some("   ")),
          rewriter.Clears(Some("    ")),
        ),
      ),
      rewriter.Eof(2),
    ])
}

pub fn handle_indentation_correctly_test() {
  assert Ok([
      parser.LineStart(None),
      parser.Literal("foo"),
      parser.InlineParameter("block", [
        parser.Literal("bar"),
      ]),
      parser.Literal("\n"),
      parser.LineStart(None),
      parser.Literal("baz"),
    ])
    == parser.parse([
      rewriter.LineStart(1, None),
      rewriter.Literal(1, "foo"),
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, "bar"),
      rewriter.End(
        1,
        ["block"],
        rewriter.Clearance(rewriter.NotClears, rewriter.Clears(Some("\n"))),
      ),
      rewriter.LineStart(2, None),
      rewriter.Literal(2, "baz"),
      rewriter.Eof(2),
    ])

  assert Ok([
      parser.Parameter("block", Some("  "), []),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.Clears(Some("  ")), rewriter.NotClears),
        ),
      ),
      rewriter.End(
        1,
        ["block"],
        rewriter.Clearance(rewriter.NotClears, rewriter.Clears(None)),
      ),
      rewriter.Eof(1),
    ])
  assert Ok([parser.Parameter("block", Some("  "), [])])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(
            rewriter.Clears(Some("  ")),
            rewriter.Clears(Some("\n")),
          ),
        ),
      ),
      rewriter.End(
        2,
        ["block"],
        rewriter.Clearance(rewriter.Clears(Some("  ")), rewriter.Clears(None)),
      ),
      rewriter.Eof(1),
    ])
}

pub fn standalone_parameter_absorbs_indent_test() {
  assert Ok([
      parser.Parameter("block", Some("  "), [
        parser.Literal("content"),
      ]),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.Clears(Some("  ")), rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, "content"),
      rewriter.End(
        1,
        ["block"],
        rewriter.Clearance(rewriter.NotClears, rewriter.Clears(None)),
      ),
      rewriter.Eof(1),
    ])
}

pub fn inline_parameter_restores_leading_test() {
  assert Ok([
      parser.LineStart(Some("  ")),
      parser.InlineParameter("block", [
        parser.Literal("content"),
      ]),
      parser.Literal("foo"),
    ])
    == parser.parse([
      rewriter.BlockStart(
        1,
        rewriter.StartTagData(
          "block",
          rewriter.Clearance(rewriter.Clears(Some("  ")), rewriter.NotClears),
        ),
      ),
      rewriter.Literal(1, "content"),
      rewriter.End(
        1,
        ["block"],
        rewriter.Clearance(rewriter.NotClears, rewriter.NotClears),
      ),
      rewriter.Literal(1, "foo"),
      rewriter.Eof(1),
    ])
}
