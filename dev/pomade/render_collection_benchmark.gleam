import gleam/dict
import gleam/list
import gleam/option.{None}

import glychee/benchmark

import pomade

const template = "
{{#products}}
  <div class='product_brick'>
    <div class='container'>
      <div class='element'>
        <img src='images/{{image}}' class='product_miniature' />
      </div>
      <div class='element description'>
        <a href={{url}} class='product_name block bold'>
          {{external_index}}
        </a>
      </div>
    </div>
  </div>
{{/products}}
"

pub fn main() {
  // Configuration is optional
  // configuration.initialize()
  // configuration.set_pair(configuration.Warmup, 2)
  // configuration.set_pair(configuration.Parallel, 2)

  // compile template beforehand, as the Ruby benchmarks do
  let assert Ok(compiled) = pomade.compile(template)

  let data =
    pomade.dict(
      dict.from_list([
        #("external_index", pomade.string("product")),
        #("url", pomade.string("/products/7")),
        #("image", pomade.string("products/product.jpg")),
      ]),
    )

  // Run the benchmarks
  benchmark.run(
    [
      benchmark.Function(label: "render collection", callable: fn(args) {
        let #(template, data) = args
        fn() { pomade.apply(template, data, None) }
      }),
    ],
    [
      benchmark.Data(label: "render list of 10", data: #(
        compiled,
        pomade.dict(
          dict.from_list([#("products", pomade.list(list.repeat(data, 10)))]),
        ),
      )),
      benchmark.Data(label: "render list of 100", data: #(
        compiled,
        pomade.dict(
          dict.from_list([#("products", pomade.list(list.repeat(data, 100)))]),
        ),
      )),
      benchmark.Data(label: "render list of 1000", data: #(
        compiled,
        pomade.dict(
          dict.from_list([#("products", pomade.list(list.repeat(data, 1000)))]),
        ),
      )),
    ],
  )
}
