import gleam/dict
import gleam/list

import glychee/benchmark

import pomade

const template = "
<h2>Names</h2>
{{#names}}
  {{> user}}
{{/names}}
"

const partial = "
<strong>{{name}}</strong>
"

pub fn main() {
  // Configuration is optional
  // configuration.initialize()
  // configuration.set_pair(configuration.Warmup, 2)
  // configuration.set_pair(configuration.Parallel, 2)

  // compile template beforehand, as the Ruby benchmarks do
  let assert Ok(compiled) = pomade.compile(template)

  let data =
    pomade.dict(dict.from_list([#("name", pomade.string("Charlie Chaplin"))]))

  let partials = dict.from_list([#("user", partial)])

  // Run the benchmarks
  benchmark.run(
    [
      benchmark.Function(label: "render collection", callable: fn(args) {
        let #(template, data, partials) = args
        fn() { pomade.apply(template, data, partials) }
      }),
    ],
    [
      benchmark.Data(label: "render list of 10", data: #(
        compiled,
        pomade.dict(
          dict.from_list([#("names", pomade.list(list.repeat(data, 10)))]),
        ),
        partials,
      )),
      benchmark.Data(label: "render list of 100", data: #(
        compiled,
        pomade.dict(
          dict.from_list([#("names", pomade.list(list.repeat(data, 100)))]),
        ),
        partials,
      )),
      benchmark.Data(label: "render list of 1000", data: #(
        compiled,
        pomade.dict(
          dict.from_list([#("names", pomade.list(list.repeat(data, 1000)))]),
        ),
        partials,
      )),
    ],
  )
}
