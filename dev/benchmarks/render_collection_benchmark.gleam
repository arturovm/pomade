import gleam/dict
import gleam/list

import glychee/benchmark

import chaplin
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
  let assert Ok(pomade_compiled) = pomade.compile(template)
  let pomade_data =
    pomade.dict(
      dict.from_list([
        #("external_index", pomade.string("product")),
        #("url", pomade.string("/products/7")),
        #("image", pomade.string("products/product.jpg")),
      ]),
    )

  let assert Ok(chaplin_compiled) = chaplin.compile(template)
  let chaplin_data = [
    #("external_index", chaplin.string("product")),
    #("url", chaplin.string("/products/7")),
    #("image", chaplin.string("products/product.jpg")),
  ]

  benchmark.run(
    [
      benchmark.Function(label: "pomade: render collection", callable: fn(args) {
        let #(template, data, _, _) = args
        fn() {
          let _ = pomade.expand(template, data, dict.new())
          Nil
        }
      }),
      benchmark.Function(
        label: "chaplin: render collection",
        callable: fn(args) {
          let #(_, _, template, data) = args
          fn() {
            let _ = chaplin.render(template, data)
            Nil
          }
        },
      ),
    ],
    [
      benchmark.Data(
        label: "render list of 10",
        data: #(
          pomade_compiled,
          pomade.dict(
            dict.from_list([
              #("products", pomade.list(list.repeat(pomade_data, 10))),
            ]),
          ),
          chaplin_compiled,
          [
            #(
              "products",
              chaplin.list(list.repeat(chaplin.object(chaplin_data), 10)),
            ),
          ],
        ),
      ),
      benchmark.Data(
        label: "render list of 100",
        data: #(
          pomade_compiled,
          pomade.dict(
            dict.from_list([
              #("products", pomade.list(list.repeat(pomade_data, 100))),
            ]),
          ),
          chaplin_compiled,
          [
            #(
              "products",
              chaplin.list(list.repeat(chaplin.object(chaplin_data), 100)),
            ),
          ],
        ),
      ),
      benchmark.Data(
        label: "render list of 1000",
        data: #(
          pomade_compiled,
          pomade.dict(
            dict.from_list([
              #("products", pomade.list(list.repeat(pomade_data, 1000))),
            ]),
          ),
          chaplin_compiled,
          [
            #(
              "products",
              chaplin.list(list.repeat(chaplin.object(chaplin_data), 1000)),
            ),
          ],
        ),
      ),
    ],
  )
}
