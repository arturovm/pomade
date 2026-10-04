import gleam/dict

import glychee/benchmark

import chaplin
import pomade

const template = "
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
"

pub fn main() {
  benchmark.run(
    [
      benchmark.Function(label: "pomade: html escape", callable: fn(args) {
        let #(template, data, _) = args
        fn() {
          let assert Ok(compiled) = pomade.compile(template)
          let _ = pomade.apply(compiled, data, dict.new())
          Nil
        }
      }),
      benchmark.Function(label: "chaplin: html escape", callable: fn(args) {
        let #(template, _, data) = args
        fn() {
          let assert Ok(compiled) = chaplin.compile(template)
          let _ = chaplin.render(compiled, data)
          Nil
        }
      }),
    ],
    [
      benchmark.Data(
        label: "data without escaping",
        data: #(
          template,
          pomade.dict(
            dict.from_list([
              #("external_index", pomade.string("product")),
              #("url", pomade.string("/products/7")),
              #("image", pomade.string("products/product.jpg")),
            ]),
          ),
          [#("external_index", chaplin.string(""))],
        ),
      ),
      benchmark.Data(
        label: "data with escaping",
        data: #(
          template,
          pomade.dict(
            dict.from_list([
              #("external_index", pomade.string("<h1>Bear > Shark</h1>")),
              #("url", pomade.string("/<h1>Bear > Shark</h1>/7")),
              #("image", pomade.string("products/<h1>Bear > Shark</h1>.jpg")),
            ]),
          ),
          [#("external_index", chaplin.string(""))],
        ),
      ),
    ],
  )
}
