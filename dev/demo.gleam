import gleam/dict
import gleam/string_tree.{type StringTree}

import pomade

pub fn precompile() -> Result(StringTree, pomade.Error) {
  let template_source = "Hello, {{target}}!"
  let assert Ok(template) = pomade.compile(template_source)
  render_compiled(template)
}

pub fn render_compiled(
  template: pomade.Template,
) -> Result(StringTree, pomade.Error) {
  let data = pomade.dict(dict.from_list([#("target", pomade.string("world"))]))
  pomade.render(template, data, dict.new())
  // -> Ok(StringTree)
  // -> "Hello, world!"
}

pub fn render_with_partials() -> Result(StringTree, pomade.Error) {
  let template_source = "Fly, you {{>other_template}}!"
  let assert Ok(template) = pomade.compile(template_source)
  let data =
    pomade.dict(dict.from_list([#("adjective", pomade.string("fools"))]))
  let partials = dict.from_list([#("other_template", "{{adjective}}")])
  pomade.render(template, data, partials)
  // -> Ok(StringTree)
  // -> "Fly, you fools!"
}

pub fn render_partials_with_dynamic_names() -> Result(StringTree, pomade.Error) {
  let template_source = "1.21 {{>*dig.down}}!"
  let assert Ok(template) = pomade.compile(template_source)
  let data =
    pomade.dict(
      dict.from_list([
        #(
          "dig",
          pomade.dict(
            dict.from_list([#("down", pomade.string("partial_name"))]),
          ),
        ),
        #("unit", pomade.string("gigawatts")),
      ]),
    )
  let partials = dict.from_list([#("partial_name", "{{unit}}")])
  pomade.render(template, data, partials)
  // -> Ok(StringTree)
  // -> "1.21 gigawatts!"
}

pub fn render_to_string() -> Result(String, pomade.Error) {
  let template_source = "Goodbye, {{target}}"
  let assert Ok(template) = pomade.compile(template_source)
  let data = pomade.dict(dict.from_list([#("target", pomade.string("horses"))]))
  pomade.render_string(template, data, dict.new())
  // -> Ok("Goodbye, horses") 
}

pub fn convenience_at_your_fingertips() -> Result(StringTree, pomade.Error) {
  let template_source = "No. I am your {{relative}}."
  let data =
    pomade.dict(dict.from_list([#("relative", pomade.string("father"))]))
  pomade.compile_and_render(template_source, data, dict.new())
  // -> Ok(StringTree)
  // -> "No. I am your father."
  //
  // Or:
  // pomade.compile_and_render_string(template_source, data, dict.new())
  // -> Ok("No. I am your father.")
}
