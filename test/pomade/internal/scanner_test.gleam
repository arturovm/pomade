import pomade/internal/scanner

pub fn empty_scanner_test() {
  assert Ok([]) == scanner.scan("")
}

pub fn scan_variable_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.Identifier(_, "person"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.RawVariable(_),
    scanner.Identifier(_, "name"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.SectionStart(_),
    scanner.Identifier(_, "person"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.ClosingTag(_),
    scanner.Identifier(_, "person"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.InvertedSectionStart(_),
    scanner.Identifier(_, "person"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{^person}}")
}

pub fn scan_partial_test_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.Partial(_),
    scanner.Identifier(_, "next_more"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{> next_more}}")
}

pub fn scan_block_start_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.BlockStart(_),
    scanner.Identifier(_, "title"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{$title}}")
}

pub fn scan_parent_start_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.ParentStart(_),
    scanner.Identifier(_, "article"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{<article}}")
}

pub fn scan_set_delimiter_start_test() {
  let assert Ok([
    scanner.SetDelimiters(_, "<%", "%>"),
    scanner.LeftDelimiter(_),
    scanner.Identifier(_, "variable"),
    scanner.RightDelimiter(_),
    scanner.SetDelimiters(_, "{{", "}}"),
    scanner.LeftDelimiter(_),
    scanner.Identifier(_, "another_variable"),
    scanner.RightDelimiter(_),
    scanner.SetDelimiters(_, "|||", "|||"),
    scanner.LeftDelimiter(_),
    scanner.Identifier(_, "yet_another"),
    scanner.RightDelimiter(_),
    scanner.SetDelimiters(_, "{{", "}}"),
    scanner.LeftDelimiter(_),
    scanner.Identifier(_, "finally"),
    scanner.RightDelimiter(_),
  ]) =
    scanner.scan(
      "{{=<% %>=}}<% variable %><%={{ }}=%>{{another_variable}}{{=||| |||=}}|||yet_another||||||={{ }}=|||{{finally}}",
    )
}

pub fn scan_comments_test() {
  let assert Ok([
    scanner.Text(_, "Hello,"),
    scanner.Ignored(_),
    scanner.Text(_, " world!"),
  ]) = scanner.scan("Hello,{{! this is a comment }} world!")
}

pub fn error_test() {
  let assert Error(scanner.NoMatchingTagCloseFoundError) =
    scanner.scan("{{! comment")

  let assert Error(scanner.MalformedIdentifier) = scanner.scan("{{var")
}

pub fn triple_mustache_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.Identifier(_, "some_variable"),
    scanner.RightDelimiter(_),
    scanner.LeftTripleMustache(_),
    scanner.Identifier(_, "triple_mustache"),
    scanner.RightTripleMustache(_),
    scanner.SetDelimiters(_, "<%", "%>"),
    scanner.Text(_, "{{{no_triple_mustache}}}"),
  ]) =
    scanner.scan(
      "{{some_variable}}{{{triple_mustache}}}{{=<% %>=}}{{{no_triple_mustache}}}",
    )
}

pub fn dotted_names_test() {
  let assert Ok([
    scanner.LeftDelimiter(_),
    scanner.Identifier(_, "hello"),
    scanner.Dot(_),
    scanner.Identifier(_, "world"),
    scanner.RightDelimiter(_),
  ]) = scanner.scan("{{hello.world}}")
}
