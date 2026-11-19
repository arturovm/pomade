import gleam/list

import glychee/benchmark

import pomade

const template =
  "
<h2>Names</h2>
{{#names}}
  {{> user}}
{{/names}}
"

const partial =
  "
<strong>{{name}}</strong>
"

pub fn main() {
  let assert Ok(compiled) = pomade.compile(template)
  let data = pomade.dict([#("name", pomade.string("Charlie Chaplin"))])
  let partials = [#("user", partial)]

  benchmark.run(
    [
      benchmark.Function(label: "render partials", callable: fn(args) {
        let #(template, data, partials) = args
        fn() { pomade.render(template, data, partials) }
      }),
    ],
    [
      benchmark.Data(label: "render list of 10", data: #(
        compiled,
        pomade.dict([#("names", pomade.list(list.repeat(data, 10)))]),
        partials,
      )),
      benchmark.Data(label: "render list of 100", data: #(
        compiled,
        pomade.dict([#("names", pomade.list(list.repeat(data, 100)))]),
        partials,
      )),
      benchmark.Data(label: "render list of 1000", data: #(
        compiled,
        pomade.dict([#("names", pomade.list(list.repeat(data, 1000)))]),
        partials,
      )),
    ],
  )
}
