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

  // Run the benchmarks
  benchmark.run(
    [
      benchmark.Function(label: "compile template", callable: fn(template) {
        fn() { pomade.compile(template) }
      }),
    ],
    [benchmark.Data(label: "template", data: template)],
  )
}
