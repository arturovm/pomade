import gleam/option.{None, Some}

import pomade/internal/parser
import pomade/internal/rewriter
import pomade/internal/scanner

pub fn empty_parser_test() {
  assert Ok([]) == parser.parse([rewriter.Eof(0)])
}

pub fn indent_test() {
  assert Ok([parser.Indent])
    == parser.parse([rewriter.Indent(0), rewriter.Eof(0)])
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
      parser.Section(
        ["person"],
        rewriter.End(0, ["person"], rewriter.ClearsNone, None, None),
        [parser.Variable(["name"])],
      ),
    ])
    == parser.parse([
      rewriter.SectionStart(0, ["person"]),
      rewriter.Variable(0, ["name"]),
      rewriter.End(0, ["person"], rewriter.ClearsNone, None, None),
      rewriter.Eof(0),
    ])
}

pub fn inverted_section_test() {
  assert Ok([
      parser.InvertedSection(
        ["person"],
        rewriter.End(0, ["person"], rewriter.ClearsNone, None, None),
        [parser.Literal("no repos :(")],
      ),
    ])
    == parser.parse([
      rewriter.InvertedSectionStart(0, ["person"]),
      rewriter.Literal(0, "no repos :("),
      rewriter.End(0, ["person"], rewriter.ClearsNone, None, None),
      rewriter.Eof(0),
    ])
}

pub fn block_test() {
  assert Ok([
      parser.Parameter(
        rewriter.BlockStart(0, "title", rewriter.ClearsNone, None, None),
        rewriter.End(0, ["title"], rewriter.ClearsNone, None, None),
        "",
        [
          parser.Literal("hello :)"),
        ],
      ),
    ])
    == parser.parse([
      rewriter.BlockStart(0, "title", rewriter.ClearsNone, None, None),
      rewriter.Literal(0, "hello :)"),
      rewriter.End(0, ["title"], rewriter.ClearsNone, None, None),
      rewriter.Eof(0),
    ])
}

pub fn parent_test() {
  assert Ok([
      parser.Parent(
        rewriter.ParentStart(0, "article", rewriter.ClearsNone, None, None),
        rewriter.End(0, ["article"], rewriter.ClearsNone, None, None),
        None,
        [
          parser.Literal("hello :)"),
          parser.Parameter(
            rewriter.BlockStart(0, "title", rewriter.ClearsNone, None, None),
            rewriter.End(0, ["title"], rewriter.ClearsNone, None, None),
            "",
            [
              parser.Literal("goodbye :("),
            ],
          ),
        ],
      ),
    ])
    == parser.parse([
      rewriter.ParentStart(0, "article", rewriter.ClearsNone, None, None),
      rewriter.Literal(0, "hello :)"),
      rewriter.BlockStart(0, "title", rewriter.ClearsNone, None, None),
      rewriter.Literal(0, "goodbye :("),
      rewriter.End(0, ["title"], rewriter.ClearsNone, None, None),
      rewriter.End(0, ["article"], rewriter.ClearsNone, None, None),
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
}

pub fn recursion_test() {
  assert Ok([
      parser.Literal("some text"),
      parser.Section(
        ["a_section"],
        rewriter.End(0, ["a_section"], rewriter.ClearsNone, None, None),
        [
          parser.Variable(["some_variable"]),
          parser.InvertedSection(
            ["inner_section"],
            rewriter.End(0, ["inner_section"], rewriter.ClearsNone, None, None),
            [parser.Literal("inner text")],
          ),
        ],
      ),
    ])
    == parser.parse([
      rewriter.Literal(0, "some text"),
      rewriter.SectionStart(0, ["a_section"]),
      rewriter.Variable(0, ["some_variable"]),
      rewriter.InvertedSectionStart(0, ["inner_section"]),
      rewriter.Literal(0, "inner text"),
      rewriter.End(0, ["inner_section"], rewriter.ClearsNone, None, None),
      rewriter.End(0, ["a_section"], rewriter.ClearsNone, None, None),
      rewriter.Eof(0),
    ])
}
