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
  benchmark.run(
    [
      benchmark.Function(
        label: "pomade: compile template",
        callable: fn(template) {
          fn() {
            let _ = pomade.compile(template)
            Nil
          }
        },
      ),
      benchmark.Function(
        label: "chaplin: compile template",
        callable: fn(template) {
          fn() {
            let _ = chaplin.compile(template)
            Nil
          }
        },
      ),
    ],
    [benchmark.Data(label: "template", data: template)],
  )
}
