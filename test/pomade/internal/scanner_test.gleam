import pomade/internal/scanner

pub fn empty_scanner_test() {
  assert Ok([]) == scanner.scan("")
}

pub fn scan_variable_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
  ]) = scanner.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.RawVariableIndicator,
    scanner.Identifier("name"),
    scanner.RightDelimiter,
  ]) = scanner.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.SectionIndicator,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
  ]) = scanner.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.ClosingIndicator,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
  ]) = scanner.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.InvertedSectionIndicator,
    scanner.Identifier("person"),
    scanner.RightDelimiter,
  ]) = scanner.scan("{{^person}}")
}

pub fn scan_partial_test_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.PartialIndicator,
    scanner.Identifier("next_more"),
    scanner.RightDelimiter,
  ]) = scanner.scan("{{> next_more}}")
}

pub fn scan_block_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.BlockIndicator,
    scanner.Identifier("title"),
    scanner.RightDelimiter,
  ]) = scanner.scan("{{$title}}")
}

pub fn scan_parent_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.ParentIndicator,
    scanner.Identifier("article"),
    scanner.RightDelimiter,
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
  ]) =
    scanner.scan(
      "{{=<% %>=}}<% variable %><%={{ }}=%>{{another_variable}}{{=||| |||=}}|||yet_another||||||={{ }}=|||{{finally}}",
    )
}

pub fn scan_comments_test() {
  let assert Ok([
    scanner.Text("Hello,"),
    scanner.Ignored,
    scanner.Text(" world!"),
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
    scanner.Text("{{{no_triple_mustache}}}"),
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
  ]) = scanner.scan("{{hello.world}}")
}

pub fn scan_newline_test() {
  let assert Ok([
    scanner.Text("Begin"),
    scanner.Newline("\n"),
    scanner.Text("\t"),
    scanner.Ignored,
    scanner.Newline("\n"),
    scanner.Text("End"),
  ]) = scanner.scan("Begin\n\t{{!ignore me}}\nEnd")

  let assert Ok([
    scanner.Text("Foo"),
    scanner.Newline("\r\n"),
    scanner.Text("\t"),
    scanner.Ignored,
    scanner.Newline("\n"),
    scanner.Text("Bar"),
  ]) = scanner.scan("Foo\r\n\t{{!ignore me}}\nBar")
}
