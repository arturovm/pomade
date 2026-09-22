import pomade/internal/scanner

pub fn empty_scanner_test() {
  assert Ok([scanner.Eof]) == scanner.scan("")
}

pub fn scan_whitespace_test() {
  assert Ok([scanner.WhitespaceLiteral(" "), scanner.Eof]) == scanner.scan(" ")
  assert Ok([
      scanner.WhitespaceLiteral("\t    "),
      scanner.TextLiteral("indented"),
      scanner.Eof,
    ])
    == scanner.scan("\t    indented")
  assert Ok([
      scanner.TextLiteral("hello,"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("this"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("is"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("a"),
      scanner.WhitespaceLiteral(" "),
      scanner.TextLiteral("message"),
      scanner.Eof,
    ])
    == scanner.scan("hello, this is a message")
}

pub fn scan_variable_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.RawVariableIndicator,
    scanner.Identifier("name"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.SectionIndicator,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.ClosingIndicator,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.InvertedSectionIndicator,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{^person}}")
}

pub fn scan_partial_test_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.PartialIndicator,
    scanner.Identifier("next_more"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{> next_more}}")
}

pub fn scan_block_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.BlockIndicator,
    scanner.Identifier("title"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{$title}}")
}

pub fn scan_parent_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.ParentIndicator,
    scanner.Identifier("article"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{<article}}")
}

pub fn scan_set_delimiter_start_test() {
  let assert Ok([
    scanner.SetDelimiters("<%", "%>"),
    scanner.LeftDelimiter,
    scanner.Identifier("variable"),
    scanner.RightDelimiter,
    scanner.SetDelimiters("{{", "}}"),
    scanner.LeftDelimiter,
    scanner.Identifier("another_variable"),
    scanner.RightDelimiter,
    scanner.SetDelimiters("|||", "|||"),
    scanner.LeftDelimiter,
    scanner.Identifier("yet_another"),
    scanner.RightDelimiter,
    scanner.SetDelimiters("{{", "}}"),
    scanner.LeftDelimiter,
    scanner.Identifier("finally"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) =
    scanner.scan(
      "{{=<% %>=}}<% variable %><%={{ }}=%>{{another_variable}}{{=||| |||=}}|||yet_another||||||={{ }}=|||{{finally}}",
    )
}

pub fn scan_comments_test() {
  let assert Ok([
    scanner.TextLiteral("Hello,"),
    scanner.Ignored,
    scanner.WhitespaceLiteral(" "),
    scanner.TextLiteral("world!"),
    scanner.Eof,
  ]) = scanner.scan("Hello,{{! this is a comment }} world!")
}

pub fn scanner_error_test() {
  let assert Error(scanner.UnterminatedTagError) = scanner.scan("{{! comment")
  let assert Error(scanner.UnterminatedTagError) = scanner.scan("{{var")
  let assert Error(scanner.MalformedIdentifierError) = scanner.scan("{{}}")
}

pub fn scan_triple_mustache_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.Identifier("some_variable"),
    scanner.RightDelimiter,
    scanner.LeftTripleMustache,
    scanner.Identifier("triple_mustache"),
    scanner.RightTripleMustache,
    scanner.SetDelimiters("<%", "%>"),
    scanner.TextLiteral("{{{no_triple_mustache}}}"),
    scanner.Eof,
  ]) =
    scanner.scan(
      "{{some_variable}}{{{triple_mustache}}}{{=<% %>=}}{{{no_triple_mustache}}}",
    )
}

pub fn scan_dotted_names_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.Identifier("hello"),
    scanner.Dot,
    scanner.Identifier("world"),
    scanner.RightDelimiter,
    scanner.Eof,
  ]) = scanner.scan("{{hello.world}}")
}

pub fn scan_newline_test() {
  let assert Ok([
    scanner.TextLiteral("Begin"),
    scanner.NewlineLiteral("\n"),
    scanner.WhitespaceLiteral("\t"),
    scanner.Ignored,
    scanner.NewlineLiteral("\n"),
    scanner.TextLiteral("End"),
    scanner.Eof,
  ]) = scanner.scan("Begin\n\t{{!ignore me}}\nEnd")

  let assert Ok([
    scanner.TextLiteral("Foo"),
    scanner.NewlineLiteral("\r\n"),
    scanner.WhitespaceLiteral("\t"),
    scanner.Ignored,
    scanner.NewlineLiteral("\n"),
    scanner.TextLiteral("Bar"),
    scanner.Eof,
  ]) = scanner.scan("Foo\r\n\t{{!ignore me}}\nBar")
}
