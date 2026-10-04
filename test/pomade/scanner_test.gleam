import pomade/internal/scanner

pub fn empty_scanner_test() {
  assert Ok([scanner.Eof(1)]) == scanner.scan("")
}

pub fn scan_whitespace_test() {
  assert Ok([scanner.Whitespace(1, "  "), scanner.Eof(1)]) == scanner.scan("  ")
  assert Ok([
      scanner.Text(1, "\t    indented"),
      scanner.Eof(1),
    ])
    == scanner.scan("\t    indented")
  assert Ok([
      scanner.Text(1, "hello, this is a message"),
      scanner.Eof(1),
    ])
    == scanner.scan("hello, this is a message")
  assert Ok([
      scanner.Whitespace(1, "  \t"),
      scanner.Newline(1, "\n"),
      scanner.Eof(2),
    ])
    == scanner.scan("  \t\n")
}

pub fn scan_variable_test() {
  let assert Ok([scanner.Variable(1, ["person"]), scanner.Eof(1)]) =
    scanner.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert Ok([scanner.RawVariable(1, ["name"]), scanner.Eof(1)]) =
    scanner.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert Ok([scanner.SectionStart(1, ["person"]), scanner.Eof(1)]) =
    scanner.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert Ok([scanner.End(1, ["person"]), scanner.Eof(1)]) =
    scanner.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert Ok([scanner.InvertedSectionStart(1, ["person"]), scanner.Eof(1)]) =
    scanner.scan("{{^person}}")
}

pub fn scan_partial_test() {
  let assert Ok([scanner.Partial(1, "next_more"), scanner.Eof(1)]) =
    scanner.scan("{{> next_more}}")
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
    scanner.Eof(1),
  ]) =
    scanner.scan(
      "{{=<% %>=}}<% variable %><%={{ }}=%>{{another_variable}}{{=||| |||=}}|||yet_another||||||={{ }}=|||{{finally}}",
    )
}

pub fn scan_comments_test() {
  let assert Ok([
    scanner.Text(1, "Hello,"),
    scanner.Comment(1),
    scanner.Text(1, " world!"),
    scanner.Eof(1),
  ]) = scanner.scan("Hello,{{! this is a comment }} world!")
}

pub fn scanner_error_test() {
  let assert Error(scanner.UnterminatedTagError(1)) =
    scanner.scan("{{! comment")
  let assert Error(scanner.UnterminatedTagError(1)) = scanner.scan("{{var")
  let assert Error(scanner.MalformedIdentifierError(1)) = scanner.scan("{{}}")
}

pub fn scan_triple_mustache_test() {
  let assert Ok([
    scanner.Variable(1, ["some_variable"]),
    scanner.RawVariable(1, ["triple_mustache"]),
    scanner.SetDelimiters(1, "<%", "%>"),
    scanner.Text(1, "{{{no_triple_mustache}}}"),
    scanner.Eof(1),
  ]) =
    scanner.scan(
      "{{some_variable}}{{{triple_mustache}}}{{=<% %>=}}{{{no_triple_mustache}}}",
    )
}

pub fn scan_dotted_names_test() {
  assert Ok([scanner.Variable(1, ["hello", "world"]), scanner.Eof(1)])
    == scanner.scan("{{hello.world}}")

  assert Error(scanner.UnexpectedCharacterError(1, "f"))
    == scanner.scan("{{.foo}}")
}

pub fn scan_newline_test() {
  let assert Ok([
    scanner.Text(1, "Begin"),
    scanner.Newline(1, "\n"),
    scanner.Whitespace(2, "\t"),
    scanner.Comment(2),
    scanner.Newline(2, "\n"),
    scanner.Text(3, "End"),
    scanner.Eof(3),
  ]) = scanner.scan("Begin\n\t{{!ignore me}}\nEnd")

  let assert Ok([
    scanner.Text(1, "Foo"),
    scanner.Newline(1, "\r\n"),
    scanner.Whitespace(2, "\t"),
    scanner.Comment(2),
    scanner.Newline(2, "\n"),
    scanner.Text(3, "Bar"),
    scanner.Eof(3),
  ]) = scanner.scan("Foo\r\n\t{{!ignore me}}\nBar")
}

pub fn scan_multiline_comment_test() {
  let assert Ok([
    scanner.Text(1, "12345"),
    scanner.Comment(1),
    scanner.Text(1, "67890"),
    scanner.Newline(1, "\n"),
    scanner.Eof(2),
  ]) = scanner.scan("12345{{!\n  This is a\n  multi-line comment...\n}}67890\n")
}
