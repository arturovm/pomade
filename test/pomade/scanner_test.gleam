import pomade/internal/scanner

pub fn empty_scanner_test() {
  assert Ok([scanner.Eof]) == scanner.scan("")
}

pub fn scan_whitespace_test() {
  assert Ok([scanner.Whitespace(1, " "), scanner.Eof]) == scanner.scan(" ")
  assert Ok([
      scanner.Whitespace(1, "\t    "),
      scanner.Text(1, "indented"),
      scanner.Eof,
    ])
    == scanner.scan("\t    indented")
  assert Ok([
      scanner.Text(1, "hello,"),
      scanner.Whitespace(1, " "),
      scanner.Text(1, "this"),
      scanner.Whitespace(1, " "),
      scanner.Text(1, "is"),
      scanner.Whitespace(1, " "),
      scanner.Text(1, "a"),
      scanner.Whitespace(1, " "),
      scanner.Text(1, "message"),
      scanner.Eof,
    ])
    == scanner.scan("hello, this is a message")
}

pub fn scan_variable_test() {
  let assert Ok([scanner.Variable(1, ["person"]), scanner.Eof]) =
    scanner.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert Ok([scanner.RawVariable(1, ["name"]), scanner.Eof]) =
    scanner.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert Ok([scanner.SectionStart(1, ["person"]), scanner.Eof]) =
    scanner.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert Ok([scanner.End(1, ["person"]), scanner.Eof]) =
    scanner.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert Ok([scanner.InvertedSectionStart(1, ["person"]), scanner.Eof]) =
    scanner.scan("{{^person}}")
}

pub fn scan_partial_test() {
  let assert Ok([scanner.Partial(1, "next_more"), scanner.Eof]) =
    scanner.scan("{{> next_more}}")
}

pub fn scan_block_start_test() {
  let assert Ok([scanner.BlockStart(1, ["title"]), scanner.Eof]) =
    scanner.scan("{{$title}}")
}

pub fn scan_parent_start_test() {
  let assert Ok([scanner.ParentStart(1, ["article"]), scanner.Eof]) =
    scanner.scan("{{<article}}")
}

pub fn scan_set_delimiter_start_test() {
  let assert Ok([
    scanner.SetDelimiters(1, "<%", "%>"),
    scanner.Variable(1, ["variable"]),
    scanner.SetDelimiters(1, "{{", "}}"),
    scanner.Variable(1, ["another_variable"]),
    scanner.SetDelimiters(1, "|||", "|||"),
    scanner.Variable(1, ["yet_another"]),
    scanner.SetDelimiters(1, "{{", "}}"),
    scanner.Variable(1, ["finally"]),
    scanner.Eof,
  ]) =
    scanner.scan(
      "{{=<% %>=}}<% variable %><%={{ }}=%>{{another_variable}}{{=||| |||=}}|||yet_another||||||={{ }}=|||{{finally}}",
    )
}

pub fn scan_comments_test() {
  let assert Ok([
    scanner.Text(1, "Hello,"),
    scanner.Comment(1),
    scanner.Whitespace(1, " "),
    scanner.Text(1, "world!"),
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
    scanner.Variable(1, ["some_variable"]),
    scanner.RawVariable(1, ["triple_mustache"]),
    scanner.SetDelimiters(1, "<%", "%>"),
    scanner.Text(1, "{{{no_triple_mustache}}}"),
    scanner.Eof,
  ]) =
    scanner.scan(
      "{{some_variable}}{{{triple_mustache}}}{{=<% %>=}}{{{no_triple_mustache}}}",
    )
}

pub fn scan_dotted_names_test() {
  let assert Ok([scanner.Variable(1, ["hello", "world"]), scanner.Eof]) =
    scanner.scan("{{hello.world}}")
}

pub fn scan_newline_test() {
  let assert Ok([
    scanner.Text(1, "Begin"),
    scanner.Newline(1, "\n"),
    scanner.Whitespace(2, "\t"),
    scanner.Comment(2),
    scanner.Newline(2, "\n"),
    scanner.Text(3, "End"),
    scanner.Eof,
  ]) = scanner.scan("Begin\n\t{{!ignore me}}\nEnd")

  let assert Ok([
    scanner.Text(1, "Foo"),
    scanner.Newline(1, "\r\n"),
    scanner.Whitespace(2, "\t"),
    scanner.Comment(2),
    scanner.Newline(2, "\n"),
    scanner.Text(3, "Bar"),
    scanner.Eof,
  ]) = scanner.scan("Foo\r\n\t{{!ignore me}}\nBar")

  let assert Error(scanner.UnexpectedCharacterError("f")) =
    scanner.scan("{{.foo}}")
}

pub fn scan_multiline_comment_test() {
  let assert Ok([
    scanner.Text(1, "12345"),
    scanner.Comment(1),
    scanner.Text(1, "67890"),
    scanner.Newline(1, "\n"),
    scanner.Eof,
  ]) = scanner.scan("12345{{!\n  This is a\n  multi-line comment...\n}}67890\n")
}
