import gleam/dict

import gleeunit

import pomade

import pomade/internal/value.{Dict, String}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn render_test() {
  let template_source = "hello, {{greeting}}!"

  assert Ok("hello, world!")
    == pomade.render(
      template_source,
      Dict(dict.from_list([#("greeting", String("world"))])),
      dict.new(),
    )
  assert Ok("hello, Joe!")
    == pomade.render(
      template_source,
      Dict(dict.from_list([#("greeting", String("Joe"))])),
      dict.new(),
    )
}

pub fn compile_test() {
  let assert Ok(template) = pomade.compile("I get {{direction}}")

  assert Ok("I get up")
    == pomade.apply(
      template,
      Dict(dict.from_list([#("direction", String("up"))])),
      dict.new(),
    )
  assert Ok("I get down")
    == pomade.apply(
      template,
      Dict(dict.from_list([#("direction", String("down"))])),
      dict.new(),
    )
}

pub fn passing_value_as_env_test() {
  let assert Ok(template) = pomade.compile("This is {{.}}")

  assert Ok("This is great")
    == pomade.apply(template, String("great"), dict.new())
}
