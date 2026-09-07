import wax/internal/scanner

pub fn empty_scanner_test() {
  assert [] == scanner.scan("")
}

pub fn scan_variable_test() {
  let assert [scanner.Variable(_, "person")] = scanner.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert [scanner.RawVariable(_, "name")] = scanner.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert [scanner.SectionStart(_, "person")] = scanner.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert [scanner.ClosingTag(_, "person")] = scanner.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert [scanner.InvertedSectionStart(_, "person")] =
    scanner.scan("{{^person}}")
}

pub fn scan_partial_test() {
  let assert [scanner.Partial(_, "next_more")] = scanner.scan("{{> next_more}}")
}

pub fn scan_block_start() {
  let assert [scanner.BlockStart(_, "title")] = scanner.scan("{{$title}}")
}

pub fn scan_parent_start() {
  let assert [scanner.BlockStart(_, "article")] = scanner.scan("{{<article}}")
}

pub fn scan_set_delimiter_start_test() {
  let assert [
    scanner.SetDelimiters(_, "<%", "%>"),
    scanner.Variable(_, "variable"),
    scanner.SetDelimiters(_, "{{", "}}"),
    scanner.Variable(_, "another_variable"),
  ] = scanner.scan("{{=<% %>=}}<% variable %><%={{ }}=%>{{another_variable}}")
}

pub fn scan_comments_test() {
  let assert [
    scanner.Text(_, "Hello,"),
    scanner.Comment(_),
    scanner.Text(_, " world!"),
  ] = scanner.scan("Hello,{{! this is a comment }} world!")
}
