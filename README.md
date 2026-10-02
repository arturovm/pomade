# pomade

_Add a little Gleam to your Mustache_

[![Package Version](https://img.shields.io/hexpm/v/pomade)](https://hex.pm/packages/pomade)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://pomade.hexdocs.pm/)

## Tabe of contents

- [What](#what)
  - [Compatibility](#compatibility)
- [How](#how)
  - [Installing it](#installing-it)
  - [Using it](#using-it)
    - [Rendering templates](#rendering-template)
    - [Using partials](#using-partials)
    - [Pre-compilation](#pre-compilation)
- [Information for nerds](#information-for-nerds)
  - [Working on it](#working-on-it)
  - [Benchmarking it](#benchmarking-it)
    - [Results](#results)
- [License](#license)
- [Important](#important)


## What

`pomade` is a [Mustache](https://mustache.github.io) library written in Gleam. I
made it primarily because I couldn't find a pure Gleam implementation of the
Mustache templating language, but also because I wanted to make something fun
and learn Gleam in the process.

### Compatibility

The goal for version 1.0 is to fully support the required portions of the
Mustache specification, which means:

- Variables
- Raw variables
- Custom delimiters
- Sections
- Inverted sections
- Partials

As of version 0.0.1, this target has been achieved, but no support for the
optional parts of the specification is planned before the first stable release.
These unsupported aspects are:

- Inheritance (blocks and parents)
- Lambdas and functions

`pomade` passes the full [suite of tests](https://github.com/mustache/spec) for
the mandatory features of the specification.

## How

### Installing it

```sh
gleam add pomade@1
```
### Using it

First, import the required libraries:

```gleam
import gleam/dict
import gleam/option.{None, Some}

import pomade
import pomade/value
```

`pomade/value` is necessary because Mustache supports heterogeneous hashmaps
and values as input, which Gleam does not (understandably) support on the
native `gleam/dict` module and type

#### Rendering templates

The most basic use case is rendering a template with a single call:

```gleam
pub fn render_template() -> Result(String, pomade.Error) {
  let template = "Hello, {{target}}!"
  let data = value.Dict(dict.from_list([#("target", value.String("world"))]))
  pomade.render(template, data, None)
  // -> Ok(StringTree)
  // -> "Hello, world!"
}
```

By default, the API returns `StringTree`s, but there's also a version that
returns `String`s:

```gleam
pub fn render_string() -> Result(String, pomade.Error) {
  let template = "Goodbye, {{target}}"
  let data = value.Dict(dict.from_list([#("target", value.String("horses"))]))
  pomade.render_string(template, data, None)
  // -> Ok("Goodbye, horses") 
}
```

#### Using partials

You can also render templates with partials, by passing a `Dict(String, String)`
in the partials argument, mapping a partial name to the source of that partial:

```gleam
pub fn render_with_partials() -> Result(String, String) {
  let template = "Fly, you {{>other_template}}!"
  let data = value.Dict(dict.from_list([#("adjective", value.String("fools"))]))
  let partials = dict.from_list([#("other_template", "{{adjective}}")])
  pomade.render_string(template, data, Some(partials))
  // -> Ok("Fly, you fools!")
}
```

#### Pre-compilation

If you anticipate that you'll be rendering a template often during the lifespan
of your program (as in, for example, a web application), you can pre-compile
templates to save some time:

```gleam
pub fn precompile() -> Result(String, String) {
  let template_source = "No. I am your {{relative}}."
  let assert Ok(template) = pomade.compile(template_source)
  render_compiled(template)
}
```

You can then, of course, simply apply the pre-compiled template:

```gleam
pub fn render_compiled(
  template: pomade.Template,
) -> Result(String, String) {
  let data = value.Dict(dict.from_list([#("relative", value.String("father"))]))
  pomade.apply_string(template, data, None)
  // -> Ok("No. I am your father.")
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

`pomade` comes with a few Glychee benchmarks, lifted (ported) shamelessly from
the repository of the Ruby version of Mustache. You can find them under
`dev/pomade`, and you can run them like so:

```sh
gleam run -m "pomade/compile_template_benchmark"
```

#### Results

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
Name                       ips        average  deviation         median         99th %
compile template       33.16 K       30.16 μs     ±9.96%       28.38 μs       39.50 μs

Memory usage statistics:

Name                Memory usage
compile template        65.02 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name             Reduction count
compile template          5.57 K

**All measurements for reduction count were the same**
```

##### Render template without HTML escaping

```
Name                  ips        average  deviation         median         99th %
html escape       35.10 K       28.49 μs    ±11.23%       26.92 μs          37 μs

Memory usage statistics:

Name           Memory usage
html escape        57.71 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name        Reduction count
html escape          5.07 K

**All measurements for reduction count were the same**
```

##### Render template with HTML escaping

```
Name                  ips        average  deviation         median         99th %
html escape       34.56 K       28.94 μs     ±9.49%       27.50 μs       35.08 μs

Memory usage statistics:

Name           Memory usage
html escape        57.71 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name        Reduction count
html escape          5.14 K

**All measurements for reduction count were the same**
```

##### Render pre-compiled template with a collection with 1000 items

```
Name                        ips        average  deviation         median         99th %
render collection        1.66 K      600.92 μs    ±10.27%      584.13 μs      771.54 μs

Memory usage statistics:

Name                 Memory usage
render collection       797.14 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name              Reduction count
render collection        129.25 K

**All measurements for reduction count were the same**
```

##### Render pre-compiled template with a collection with 1000 partials

```
Name                      ips        average  deviation         median         99th %
render partials        4.43 K      225.84 μs    ±17.35%      215.67 μs      379.92 μs

Memory usage statistics:

Name               Memory usage
render partials       523.53 KB

**All measurements for memory usage were the same**

Reduction count statistics:

Name            Reduction count
render partials         67.28 K

**All measurements for reduction count were the same**
```

## License

`pomade` is distributed under the MIT License. You can find more details in
`LICENSE`.

## Important

You won't find any AI slop here.
