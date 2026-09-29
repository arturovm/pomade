import gleam/dict
import gleam/option.{None}

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
      None,
    )
  assert Ok("hello, Joe!")
    == pomade.render(
      template_source,
      Dict(dict.from_list([#("greeting", String("Joe"))])),
      None,
    )
}

pub fn compile_test() {
  let assert Ok(template) = pomade.compile("I get {{direction}}")

  assert Ok("I get up")
    == pomade.apply(
      template,
      Dict(dict.from_list([#("direction", String("up"))])),
      None,
    )
  assert Ok("I get down")
    == pomade.apply(
      template,
      Dict(dict.from_list([#("direction", String("down"))])),
      None,
    )
}

pub fn passing_value_as_env_test() {
  let assert Ok(template) = pomade.compile("This is {{.}}")

  assert Ok("This is great") == pomade.apply(template, String("great"), None)
}
