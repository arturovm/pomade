import gleam/dict

import gleeunit

import pomade.{Dict, String}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn render_test() {
  let template_source = "hello, {{greeting}}!"

  assert Ok("hello, world!")
    == pomade.render(
      template_source,
      Dict(dict.from_list([#("greeting", String("world"))])),
    )
  assert Ok("hello, Joe!")
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
