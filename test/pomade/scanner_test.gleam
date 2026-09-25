import pomade/internal/scanner

pub fn empty_scanner_test() {
  assert Ok([scanner.Eof]) == scanner.scan("")
}

pub fn scan_whitespace_test() {
  assert Ok([scanner.Whitespace(" "), scanner.Eof]) == scanner.scan(" ")
  assert Ok([
      scanner.Whitespace("\t    "),
      scanner.Text("indented"),
      scanner.Eof,
    ])
    == scanner.scan("\t    indented")
  assert Ok([
      scanner.Text("hello,"),
      scanner.Whitespace(" "),
      scanner.Text("this"),
      scanner.Whitespace(" "),
      scanner.Text("is"),
      scanner.Whitespace(" "),
      scanner.Text("a"),
      scanner.Whitespace(" "),
      scanner.Text("message"),
      scanner.Eof,
    ])
    == scanner.scan("hello, this is a message")
}

pub fn scan_variable_test() {
  let assert Ok([
    scanner.Variable(["person"]),
    scanner.Eof,
  ]) = scanner.scan("{{person}}")
}

pub fn scan_raw_variable_test() {
  let assert Ok([
    scanner.RawVariable(["name"]),
    scanner.Eof,
  ]) = scanner.scan("{{& name}}")
}

pub fn scan_section_start_test() {
  let assert Ok([
    scanner.SectionStart(["person"]),
    scanner.Eof,
  ]) = scanner.scan("{{#person}}")
}

pub fn scan_closing_tag_test() {
  let assert Ok([
    scanner.End(["person"]),
    scanner.Eof,
  ]) = scanner.scan("{{/person}}")
}

pub fn scan_inverted_section_start_test() {
  let assert Ok([
    scanner.InvertedSectionStart(["person"]),
    scanner.Eof,
  ]) = scanner.scan("{{^person}}")
}

pub fn scan_partial_test_test() {
  let assert Ok([
    scanner.Partial(["next_more"]),
    scanner.Eof,
  ]) = scanner.scan("{{> next_more}}")
}

pub fn scan_block_start_test() {
  let assert Ok([
    scanner.BlockStart(["title"]),
    scanner.Eof,
  ]) = scanner.scan("{{$title}}")
}

pub fn scan_parent_start_test() {
  let assert Ok([
    scanner.ParentStart(["article"]),
    scanner.Eof,
  ]) = scanner.scan("{{<article}}")
}

pub fn scan_set_delimiter_start_test() {
  let assert Ok([
    scanner.LeftDelimiter,
    scanner.SetDelimiters("<%", "%>"),
    scanner.RightDelimiter,
    scanner.LeftDelimiter,
    scanner.Identifier("variable"),
    scanner.RightDelimiter,
    scanner.LeftDelimiter,
    scanner.SetDelimiters("{{", "}}"),
    scanner.RightDelimiter,
    scanner.LeftDelimiter,
    scanner.Identifier("another_variable"),
    scanner.RightDelimiter,
    scanner.LeftDelimiter,
    scanner.SetDelimiters("|||", "|||"),
    scanner.RightDelimiter,
    scanner.LeftDelimiter,
    scanner.Identifier("yet_another"),
    scanner.RightDelimiter,
    scanner.LeftDelimiter,
    scanner.SetDelimiters("{{", "}}"),
    scanner.RightDelimiter,
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
    scanner.Text("Hello,"),
    scanner.LeftDelimiter,
    scanner.Comment,
    scanner.RightDelimiter,
    scanner.Whitespace(" "),
    scanner.Text("world!"),
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
    scanner.LeftDelimiter,
    scanner.SetDelimiters("<%", "%>"),
    scanner.RightDelimiter,
    scanner.Text("{{{no_triple_mustache}}}"),
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
    scanner.Text("Begin"),
    scanner.Newline("\n"),
    scanner.Whitespace("\t"),
    scanner.LeftDelimiter,
    scanner.Comment,
    scanner.RightDelimiter,
    scanner.Newline("\n"),
    scanner.Text("End"),
    scanner.Eof,
  ]) = scanner.scan("Begin\n\t{{!ignore me}}\nEnd")

  let assert Ok([
    scanner.Text("Foo"),
    scanner.Newline("\r\n"),
    scanner.Whitespace("\t"),
    scanner.LeftDelimiter,
    scanner.Comment,
    scanner.RightDelimiter,
    scanner.Newline("\n"),
    scanner.Text("Bar"),
    scanner.Eof,
  ]) = scanner.scan("Foo\r\n\t{{!ignore me}}\nBar")
}

pub fn scan_multiline_comment_test() {
  let assert Ok([]) =
    scanner.scan("12345{{!\n  This is a\n  multi-line comment...\n}}67890\n")
}
