import gleam/dict

import pomade/internal/environment
import pomade/value.{Dict, Int, String}

pub fn empty_test() {
  assert "" == environment.get(Dict(dict.new()), [])
}

pub fn not_found_test() {
  assert "" == environment.get(Dict(dict.new()), ["non_existent"])
}

pub fn get_string_test() {
  let env = Dict(dict.from_list([#("foo", String("bar"))]))
  assert "bar" == environment.get(env, ["foo"])
}

pub fn get_int_test() {
  let env = Dict(dict.from_list([#("number_value", Int(2))]))
  assert "2" == environment.get(env, ["number_value"])
}

pub fn get_path_name_test() {
  let env =
    Dict(
      dict.from_list([
        #("parent", Dict(dict.from_list([#("inner", String("hello"))]))),
      ]),
    )
  assert "hello" == environment.get(env, ["parent", "inner"])
}
