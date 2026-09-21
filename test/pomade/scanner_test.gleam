import pomade

pub fn empty_scanner_test() {
  assert Ok([pomade.Eof]) == pomade.scan("")
}

pub fn scan_whitespace_test() {
  assert Ok([pomade.WhitespaceLiteral(" "), pomade.Eof]) == pomade.scan(" ")
  assert Ok([
      pomade.WhitespaceLiteral("\t    "),
      pomade.TextLiteral("indented"),
      pomade.Eof,
    ])
    == pomade.scan("\t    indented")
  assert Ok([
      pomade.TextLiteral("hello,"),
      pomade.WhitespaceLiteral(" "),
      pomade.TextLiteral("this"),
      pomade.WhitespaceLiteral(" "),
      pomade.TextLiteral("is"),
      pomade.WhitespaceLiteral(" "),
      pomade.TextLiteral("a"),
      pomade.WhitespaceLiteral(" "),
      pomade.TextLiteral("message"),
      pomade.Eof,
    ])
    == pomade.scan("hello, this is a message")
}

pub fn scan_variable_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.Identifier("person"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.RawVariableIndicator,
    pomade.Identifier("name"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.SectionIndicator,
    pomade.Identifier("person"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.ClosingIndicator,
    pomade.Identifier("person"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.InvertedSectionIndicator,
    pomade.Identifier("person"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{^person}}")
}

pub fn scan_partial_test_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.PartialIndicator,
    pomade.Identifier("next_more"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{> next_more}}")
}

pub fn scan_block_start_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.BlockIndicator,
    pomade.Identifier("title"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{$title}}")
}

pub fn scan_parent_start_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.ParentIndicator,
    pomade.Identifier("article"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{<article}}")
}

pub fn scan_set_delimiter_start_test() {
  let assert Ok([
    pomade.SetDelimiters("<%", "%>"),
    pomade.LeftDelimiter,
    pomade.Identifier("variable"),
    pomade.RightDelimiter,
    pomade.SetDelimiters("{{", "}}"),
    pomade.LeftDelimiter,
    pomade.Identifier("another_variable"),
    pomade.RightDelimiter,
    pomade.SetDelimiters("|||", "|||"),
    pomade.LeftDelimiter,
    pomade.Identifier("yet_another"),
    pomade.RightDelimiter,
    pomade.SetDelimiters("{{", "}}"),
    pomade.LeftDelimiter,
    pomade.Identifier("finally"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) =
    pomade.scan(
      "{{=<% %>=}}<% variable %><%={{ }}=%>{{another_variable}}{{=||| |||=}}|||yet_another||||||={{ }}=|||{{finally}}",
    )
}

pub fn scan_comments_test() {
  let assert Ok([
    pomade.TextLiteral("Hello,"),
    pomade.Ignored,
    pomade.WhitespaceLiteral(" "),
    pomade.TextLiteral("world!"),
    pomade.Eof,
  ]) = pomade.scan("Hello,{{! this is a comment }} world!")
}

pub fn scanner_error_test() {
  let assert Error(pomade.UnterminatedTagError) = pomade.scan("{{! comment")
  let assert Error(pomade.UnterminatedTagError) = pomade.scan("{{var")
  let assert Error(pomade.MalformedIdentifierError) = pomade.scan("{{}}")
}

pub fn scan_triple_mustache_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.Identifier("some_variable"),
    pomade.RightDelimiter,
    pomade.LeftTripleMustache,
    pomade.Identifier("triple_mustache"),
    pomade.RightTripleMustache,
    pomade.SetDelimiters("<%", "%>"),
    pomade.TextLiteral("{{{no_triple_mustache}}}"),
    pomade.Eof,
  ]) =
    pomade.scan(
      "{{some_variable}}{{{triple_mustache}}}{{=<% %>=}}{{{no_triple_mustache}}}",
    )
}

pub fn scan_dotted_names_test() {
  let assert Ok([
    pomade.LeftDelimiter,
    pomade.Identifier("hello"),
    pomade.Dot,
    pomade.Identifier("world"),
    pomade.RightDelimiter,
    pomade.Eof,
  ]) = pomade.scan("{{hello.world}}")
}

pub fn scan_newline_test() {
  let assert Ok([
    pomade.TextLiteral("Begin"),
    pomade.NewlineLiteral("\n"),
    pomade.WhitespaceLiteral("\t"),
    pomade.Ignored,
    pomade.NewlineLiteral("\n"),
    pomade.TextLiteral("End"),
    pomade.Eof,
  ]) = pomade.scan("Begin\n\t{{!ignore me}}\nEnd")

  let assert Ok([
    pomade.TextLiteral("Foo"),
    pomade.NewlineLiteral("\r\n"),
    pomade.WhitespaceLiteral("\t"),
    pomade.Ignored,
    pomade.NewlineLiteral("\n"),
    pomade.TextLiteral("Bar"),
    pomade.Eof,
  ]) = pomade.scan("Foo\r\n\t{{!ignore me}}\nBar")
}
