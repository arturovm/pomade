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
  let assert Ok([parser.Literal(rewriter.Literal(_, "hello, world!"))]) =
    parser.parse([
      rewriter.Literal(0, "hello, world!"),
      rewriter.Eof(0),
    ])
}

pub fn variable_test() {
  let assert Ok([parser.Variable(rewriter.Variable(_, ["hello"]))]) =
    parser.parse([
      rewriter.Variable(0, ["hello"]),
      rewriter.Eof(0),
    ])
}

pub fn dotted_variable_test() {
  let assert Ok([parser.Variable(rewriter.Variable(_, ["hello", "world"]))]) =
    parser.parse([
      rewriter.Variable(0, ["hello", "world"]),
      rewriter.Eof(0),
    ])
}

pub fn variable_single_dot_test() {
  let assert Ok([parser.Variable(rewriter.Variable(_, ["."]))]) =
    parser.parse([
      rewriter.Variable(0, ["."]),
      rewriter.Eof(0),
    ])
}

pub fn raw_variable_test() {
  let assert Ok([parser.RawVariable(rewriter.RawVariable(_, ["hello"]))]) =
    parser.parse([
      rewriter.RawVariable(0, ["hello"]),
      rewriter.Eof(0),
    ])
}

pub fn section_test() {
  let assert Ok([
    parser.Section(
      rewriter.SectionStart(_, ["person"]),
      [parser.Variable(rewriter.Variable(_, ["name"]))],
    ),
  ]) =
    parser.parse([
      rewriter.SectionStart(0, ["person"]),
      rewriter.Variable(0, ["name"]),
      rewriter.End(0, ["person"]),
      rewriter.Eof(0),
    ])
}

pub fn inverted_section_test() {
  let assert Ok([
    parser.InvertedSection(
      rewriter.InvertedSectionStart(_, ["person"]),
      [parser.Literal(rewriter.Literal(_, "no repos :("))],
    ),
  ]) =
    parser.parse([
      rewriter.InvertedSectionStart(0, ["person"]),
      rewriter.Literal(0, "no repos :("),
      rewriter.End(0, ["person"]),
      rewriter.Eof(0),
    ])
}

pub fn block_test() {
  assert Ok([
      parser.Block(rewriter.BlockStart(0, "title"), "", [
        parser.Literal(rewriter.Literal(0, "hello :)")),
      ]),
    ])
    == parser.parse([
      rewriter.BlockStart(0, "title"),
      rewriter.Literal(0, "hello :)"),
      rewriter.End(0, ["title"]),
      rewriter.Eof(0),
    ])
}

pub fn parent_test() {
  assert Ok([
      parser.Parent(rewriter.ParentStart(0, "article"), None, [
        parser.Literal(rewriter.Literal(0, "hello :)")),
        parser.Block(rewriter.BlockStart(0, "title"), "", [
          parser.Literal(rewriter.Literal(0, "goodbye :(")),
        ]),
      ]),
    ])
    == parser.parse([
      rewriter.ParentStart(0, "article"),
      rewriter.Literal(0, "hello :)"),
      rewriter.BlockStart(0, "title"),
      rewriter.Literal(0, "goodbye :("),
      rewriter.End(0, ["title"]),
      rewriter.End(0, ["article"]),
      rewriter.Eof(0),
    ])
}

pub fn partial_test() {
  let assert Ok([
    parser.Partial(rewriter.Partial(_, scanner.StaticName("box")), None),
  ]) =
    parser.parse([
      rewriter.Partial(0, scanner.StaticName("box")),
      rewriter.Eof(0),
    ])

  let assert Ok([
    parser.Partial(rewriter.Partial(_, scanner.StaticName("box")), Some("  \t")),
  ]) =
    parser.parse([
      rewriter.Padding(0, "  \t"),
      rewriter.Partial(0, scanner.StaticName("box")),
      rewriter.Eof(0),
    ])
}

pub fn recursion_test() {
  let assert Ok([
    parser.Literal(rewriter.Literal(_, "some text")),
    parser.Section(
      rewriter.SectionStart(_, ["a_section"]),
      [
        parser.Variable(rewriter.Variable(_, ["some_variable"])),
        parser.InvertedSection(
          rewriter.InvertedSectionStart(_, ["inner_section"]),
          [parser.Literal(rewriter.Literal(_, "inner text"))],
        ),
      ],
    ),
  ]) =
    parser.parse([
      rewriter.Literal(0, "some text"),
      rewriter.SectionStart(0, ["a_section"]),
      rewriter.Variable(0, ["some_variable"]),
      rewriter.InvertedSectionStart(0, ["inner_section"]),
      rewriter.Literal(0, "inner text"),
      rewriter.End(0, ["inner_section"]),
      rewriter.End(0, ["a_section"]),
      rewriter.Eof(0),
    ])
}
