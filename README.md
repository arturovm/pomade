# pomade

_Add a little Gleam to your Mustache_

[![Package Version](https://img.shields.io/hexpm/v/pomade)](https://hex.pm/packages/pomade)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://pomade.hexdocs.pm/)

## Why

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
pub fn render_without_partials() -> Result(String, pomade.Error) {
  let template = "Hello, {{target}}!"
  let data = value.Dict(dict.from_list([#("target", value.String("world"))]))
  pomade.render(template, data, None)
  // -> Ok("Hello, world!")
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
  pomade.render(template, data, Some(partials))
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
  pomade.apply(template, data, None)
  // -> Ok("No. I am your father.")
}
```

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

## License

`pomade` is distributed under the MIT License. You can find more details in
`LICENSE`.

## Important

You won't find any AI slop here.
