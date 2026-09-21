import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

import filepath
import simplifile

import pomade.{type Value, Dict, List}

type Test {
  Test(
    name: String,
    desc: String,
    data: Value,
    template: String,
    expected: String,
  )
}

type Tests {
  Tests(tests: List(Test))
}

const prefix = "dev/mustache/spec/specs"

fn load_tests_from_file(file_name: String) -> List(Test) {
  let path = filepath.join(prefix, file_name)
  let assert Ok(contents) = simplifile.read(path)
  let assert Ok(loaded_tests) = json.parse(contents, tests_decoder())
  loaded_tests.tests
}

fn tests_decoder() -> decode.Decoder(Tests) {
  use tests <- decode.field("tests", decode.list(test_decoder()))
  decode.success(Tests(tests:))
}

fn test_decoder() -> decode.Decoder(Test) {
  use name <- decode.field("name", decode.string)
  use desc <- decode.field("desc", decode.string)
  use data <- decode.field("data", value_decoder())
  use template <- decode.field("template", decode.string)
  use expected <- decode.field("expected", decode.string)
  decode.success(Test(name:, desc:, data:, template:, expected:))
}

fn value_decoder() -> decode.Decoder(Value) {
  use <- decode.recursive
  decode.one_of(decode.int |> decode.map(pomade.Int), [
    decode.float |> decode.map(pomade.Float),
    decode.string |> decode.map(pomade.String),
    decode.bool |> decode.map(pomade.Bool),
    list_decoder(),
    dict_decoder(),
  ])
}

fn dict_decoder() -> decode.Decoder(Value) {
  decode.dict(decode.string, decode.optional(value_decoder()))
  |> decode.map(fn(d) {
    dict.to_list(d)
    |> dict_list_values([])
    |> dict.from_list()
    |> Dict()
  })
}

fn dict_list_values(
  list: List(#(String, Option(Value))),
  acc: List(#(String, Value)),
) -> List(#(String, Value)) {
  case list {
    [] -> list.reverse(acc)
    [#(_, None), ..rest] -> dict_list_values(rest, acc)
    [#(k, Some(val)), ..rest] -> dict_list_values(rest, [#(k, val), ..acc])
  }
}

fn list_decoder() -> decode.Decoder(Value) {
  decode.list(decode.optional(value_decoder()))
  |> decode.map(fn(l) { option.values(l) |> List() })
}

fn run(loaded_test: Test) {
  let assert Ok(template) = pomade.compile(loaded_test.template)
    as loaded_test.name
  let assert Ok(result) = template(loaded_test.data) as loaded_test.name
  assert loaded_test.expected == result as loaded_test.name
}

fn run_all(tests: List(Test)) {
  list.each(tests, run)
}

pub fn comments_test() {
  let tests = load_tests_from_file("comments.json")
  run_all(tests)
}

pub fn interpolation_test() {
  let tests = load_tests_from_file("interpolation.json")
  run_all(tests)
}

pub fn sections_test() {
  let tests = load_tests_from_file("sections.json")
  run_all(tests)
}

pub fn delimiters_test() {
  let tests = load_tests_from_file("delimiters.json")
  run_all(tests)
}
