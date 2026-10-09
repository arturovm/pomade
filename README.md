# pomade

_Add a little Gleam to your Mustache_

[![Package Version](https://img.shields.io/hexpm/v/pomade)](https://hex.pm/packages/pomade)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://pomade.hexdocs.pm/)

## What

`pomade` is a [Mustache](https://mustache.github.io) library written in Gleam. I
made it primarily because I couldn't find a pure Gleam implementation of the
Mustache templating language, but also because I wanted to make something fun
and learn Gleam in the process.

### Compatibility

Version 1.0 fully supports the required portions of the Mustache specification:

- Variables
- Raw variables
- Custom delimiters
- Sections
- Inverted sections
- Partials

`pomade` passes the full [suite of tests](https://github.com/mustache/spec) for
these mandatory features.

The optional, as-of-yet unsupported aspects are:

- Dynamic names for partials
- Inheritance (blocks and parents)
- Lambdas and functions


## How

### Installing it

```sh
gleam add pomade@1
```
### Using it

First, import the required libraries:

```gleam
import gleam/dict
import gleam/string_tree.{type StringTree}

import pomade
```

In addition to the rendering and compilation API, `pomade` provides support for
heterogeneous hashmaps and values, which Mustache requires as input.

#### Rendering templates

The most basic use case is rendering a template with a single call:

```gleam
pub fn render_template() -> Result(StringTree, pomade.Error) {
  let template = "Hello, {{target}}!"
  let data = pomade.dict(dict.from_list([#("target", pomade.string("world"))]))
  pomade.compile_and_render(template, data, dict.new())
  // -> Ok(StringTree)
  // -> "Hello, world!"
}
```

By default, the API returns `StringTree`s, but there's a version that returns
`String`s:

```gleam
pub fn render_string() -> Result(String, pomade.Error) {
  let template = "Goodbye, {{target}}"
  let data = pomade.dict(dict.from_list([#("target", pomade.string("horses"))]))
  pomade.compile_and_render_string(template, data, dict.new())
  // -> Ok("Goodbye, horses") 
}
```

#### Using partials

You can also render templates with partials, by passing a `Dict(String, String)`
in the partials argument, mapping a partial name to the source of that partial:

```gleam
pub fn render_with_partials() -> Result(String, pomade.Error) {
  let template = "Fly, you {{>other_template}}!"
  let data =
    pomade.dict(dict.from_list([#("adjective", pomade.string("fools"))]))
  let partials = dict.from_list([#("other_template", "{{adjective}}")])
  pomade.compile_and_render_string(template, data, partials)
  // -> Ok("Fly, you fools!")
}
```

`pomade` takes care of caching the compiled partial, in a way that's compliant
with the Mustache spec, to save on the costs of compiling the template at
runtime every time it's needed.

#### Pre-compilation

If you anticipate that you'll be rendering a template often during the lifespan
of your program (as in, for example, a web application), you can pre-compile
templates to save some time:

```gleam
pub fn precompile() -> Result(String, pomade.Error) {
  let template_source = "No. I am your {{relative}}."
  let assert Ok(template) = pomade.compile(template_source)
  render_compiled(template)
}
```

You can then, of course, simply expand the pre-compiled template:

```gleam
pub fn render_compiled(
  template: pomade.Template,
) -> Result(String, pomade.Error) {
  let data =
    pomade.dict(dict.from_list([#("relative", pomade.string("father"))]))
  pomade.render_string(template, data, dict.new())
  // -> Ok("No. I am your father.")
  //
  // Or:
  // pomade.render(template, data, dict.new())
  // -> Ok(StringTree)
}
```

## Information for nerds

### Working on it

First, ensure that you've fetched the git submodules locally, so that the unit
tests can find the Mustache specification test suite:

```sh
git submodule update --init
```

Then, you can run:

```sh
gleam test
```

Or whatever.

### Benchmarking it

`pomade` comes with a few Glychee benchmarks, shamelessly lifted (ported) from
the repository of the Ruby version of Mustache. You can find them under
`dev/pomade`, and you can run them like so:

```sh
gleam run -m "pomade/compile_template_benchmark"
```

#### Results vs `bbmustache` (via `chaplin`)

With the following hardware and configuration:

```
Operating System: macOS
CPU Information: Apple M1
Number of Available Cores: 8
Available memory: 8 GB
Elixir 1.20.4
Erlang 29.1.1
JIT enabled: true

Benchmark suite executing with the following configuration:
warmup: 4 s
time: 4 s
memory time: 8 s
reduction time: 4 s
parallel: 1
inputs: none specified
Estimated total run time: 20 s
Excluding outliers: false
```

We have the following benchmarks:

##### Compile template benchmark

```
Name                                ips        average  deviation         median         99th %
pomade: compile template        82.27 K       12.15 μs    ±27.74%       11.54 μs       16.13 μs
chaplin: compile template       40.84 K       24.48 μs    ±12.77%       23.88 μs       32.54 μs

Comparison:
pomade: compile template        82.27 K
chaplin: compile template       40.84 K - 2.01x slower +12.33 μs

Memory usage statistics:

Name                         Memory usage
pomade: compile template         27.85 KB
chaplin: compile template         5.68 KB - 0.20x memory usage -22.17188 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name                      Reduction count
pomade: compile template           1.52 K
chaplin: compile template          0.40 K - 0.26x reduction count -1.12800 K

**All measurements for reduction count were the same**
```

##### Render template without HTML escaping

```
Name                           ips        average  deviation         median         99th %
pomade: html escape        83.71 K       11.95 μs    ±27.42%       10.92 μs       23.71 μs
chaplin: html escape       46.16 K       21.66 μs    ±13.53%       21.17 μs       30.08 μs

Comparison:
pomade: html escape        83.71 K
chaplin: html escape       46.16 K - 1.81x slower +9.72 μs

Memory usage statistics:

Name                    Memory usage
pomade: html escape         23.79 KB
chaplin: html escape         7.23 KB - 0.30x memory usage -16.56250 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name                 Reduction count
pomade: html escape           1.36 K
chaplin: html escape          0.65 K - 0.48x reduction count -0.71000 K

**All measurements for reduction count were the same**
```

##### Render template with HTML escaping

```
Name                           ips        average  deviation         median         99th %
pomade: html escape        82.00 K       12.19 μs    ±30.01%       11.50 μs       17.29 μs
chaplin: html escape       43.12 K       23.19 μs    ±14.29%       22.54 μs       42.17 μs

Comparison:
pomade: html escape        82.00 K
chaplin: html escape       43.12 K - 1.90x slower +11.00 μs

Memory usage statistics:

Name                    Memory usage
pomade: html escape         23.79 KB
chaplin: html escape         8.45 KB - 0.36x memory usage -15.34375 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name                 Reduction count
pomade: html escape           1.43 K
chaplin: html escape          0.90 K - 0.63x reduction count -0.53400 K

**All measurements for reduction count were the same**
```

##### Render pre-compiled template with a collection with 1000 items

```
Name                                 ips        average  deviation         median         99th %
pomade: render collection         1.73 K        0.58 ms    ±11.12%        0.56 ms        0.76 ms
chaplin: render collection        0.35 K        2.88 ms     ±4.14%        2.90 ms        3.09 ms

Comparison:
pomade: render collection         1.73 K
chaplin: render collection        0.35 K - 4.97x slower +2.30 ms

Memory usage statistics:

Name                          Memory usage
pomade: render collection          0.78 MB
chaplin: render collection         2.98 MB - 3.83x memory usage +2.20 MB

**All measurements for memory usage were the same**

Reduction count statistics:

Name                       Reduction count
pomade: render collection         129.29 K
chaplin: render collection        376.78 K - 2.91x reduction count +247.49 K

**All measurements for reduction count were the same**
```

##### Render pre-compiled template with a collection with 1000 partials

```
Name                      ips        average  deviation         median         99th %
render partials        3.91 K      256.07 μs    ±17.10%      244.83 μs      435.27 μs

Memory usage statistics:

Name               Memory usage
render partials       521.98 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name            Reduction count
render partials         66.84 K

**All measurements for reduction count were the same**
```

## License

`pomade` is distributed under the MIT License. You can find more details in
`LICENSE`.

## Important

You won't find any AI slop here.
