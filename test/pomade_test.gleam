import gleam/dict

import gleeunit

import pomade
import pomade/value.{String}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn render_test() {
  let template_source = "hello, {{greeting}}!"

  assert "hello, world!"
    == pomade.render(
      template_source,
      dict.from_list([#("greeting", String("world"))]),
    )
  assert "hello, Joe!"
    == pomade.render(
      template_source,
      dict.from_list([#("greeting", String("Joe"))]),
    )
}

pub fn compile_test() {
  let assert Ok(template) = pomade.compile("I get {{direction}}")

  assert Ok("I get up")
    == template(dict.from_list([#("direction", String("up"))]))
  assert Ok("I get down")
    == template(dict.from_list([#("direction", String("down"))]))
}
