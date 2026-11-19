import gleam/dict

import gleeunit

import pomade

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn render_test() {
  let template_source = "hello, {{greeting}}!"

  assert Ok("hello, world!")
    == pomade.compile_and_render_string(
      template_source,
      pomade.dict([#("greeting", pomade.string("world"))]),
      dict.new(),
    )
  assert Ok("hello, Joe!")
    == pomade.compile_and_render_string(
      template_source,
      pomade.dict([#("greeting", pomade.string("Joe"))]),
      dict.new(),
    )
}

pub fn compile_test() {
  let assert Ok(template) = pomade.compile("I get {{direction}}")

  assert Ok("I get up")
    == pomade.render_string(
      template,
      pomade.dict([#("direction", pomade.string("up"))]),
      dict.new(),
    )
  assert Ok("I get down")
    == pomade.render_string(
      template,
      pomade.dict([#("direction", pomade.string("down"))]),
      dict.new(),
    )
}

pub fn passing_value_as_env_test() {
  let assert Ok(template) = pomade.compile("This is {{.}}")

  assert Ok("This is great")
    == pomade.render_string(template, pomade.string("great"), dict.new())
}
