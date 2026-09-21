import gleam/dict

import gleeunit

import pomade.{Dict, String}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn render_test() {
  let template_source = "hello, {{greeting}}!"

  assert "hello, world!"
    == pomade.render(
      template_source,
      Dict(dict.from_list([#("greeting", String("world"))])),
    )
  assert "hello, Joe!"
    == pomade.render(
      template_source,
      Dict(dict.from_list([#("greeting", String("Joe"))])),
    )
}

pub fn compile_test() {
  let assert Ok(template) = pomade.compile("I get {{direction}}")

  assert Ok("I get up")
    == template(Dict(dict.from_list([#("direction", String("up"))])))
  assert Ok("I get down")
    == template(Dict(dict.from_list([#("direction", String("down"))])))
}

pub fn passing_value_as_env_test() {
  let assert Ok(template) = pomade.compile("This is {{.}}")

  assert Ok("This is great") == template(String("great"))
}

pub fn indented_standalone_test() {
  let assert Ok(tokens) = pomade.scan("Begin.\n  {{! Indented Comment Block! }}\nEnd.\n")
  assert [
    pomade.TextLiteral("Begin."),
    pomade.NewlineLiteral("\n"),
    pomade.WhitespaceLiteral("  "),
    pomade.Ignored,
    pomade.NewlineLiteral("\n"),
    pomade.TextLiteral("End."),
    pomade.NewlineLiteral("\n"),
    pomade.Eof,
  ] == tokens

  let assert Ok(ast) = pomade.parse(tokens)
  assert [
    pomade.Text("Begin."),
    pomade.Newline("\n"),
    pomade.Text("End."),
    pomade.Newline("\n"),
  ] == ast
}

pub fn indented_inline_test() {
  let assert Ok(tokens) = pomade.scan("  12 {{! 34 }}\n")
  assert [
    pomade.WhitespaceLiteral("  "),
    pomade.TextLiteral("12"),
    pomade.WhitespaceLiteral(" "),
    pomade.Ignored,
    pomade.NewlineLiteral("\n"),
    pomade.Eof,
  ] == tokens

  let assert Ok(ast) = pomade.parse(tokens)
  assert [
    pomade.Whitespace("  "),
    pomade.Text("12"),
    pomade.Whitespace(" "),
    pomade.Newline("\n"),
  ] == ast
}
