import gleam/dict
import gleam/option.{Some}

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
      Some(Dict(dict.from_list([#("greeting", Some(String("world")))]))),
    )
  assert "hello, Joe!"
    == pomade.render(
      template_source,
      Some(Dict(dict.from_list([#("greeting", Some(String("Joe")))]))),
    )
}

pub fn compile_test() {
  let assert Ok(template) = pomade.compile("I get {{direction}}")

  assert Ok("I get up")
    == template(
      Some(Dict(dict.from_list([#("direction", Some(String("up")))]))),
    )
  assert Ok("I get down")
    == template(
      Some(Dict(dict.from_list([#("direction", Some(String("down")))]))),
    )
}

pub fn passing_value_as_env_test() {
  let assert Ok(template) = pomade.compile("This is {{.}}")

  assert Ok("This is great") == template(Some(String("great")))
}
