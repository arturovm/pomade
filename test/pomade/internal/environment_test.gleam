import gleam/dict

import pomade.{Dict, Int, String}

pub fn empty_test() {
  assert "" == pomade.get(Dict(dict.new()), [])
}

pub fn not_found_test() {
  assert "" == pomade.get(Dict(dict.new()), ["non_existent"])
}

pub fn get_string_test() {
  let env = Dict(dict.from_list([#("foo", String("bar"))]))
  assert "bar" == pomade.get(env, ["foo"])
}

pub fn get_int_test() {
  let env = Dict(dict.from_list([#("number_value", Int(2))]))
  assert "2" == pomade.get(env, ["number_value"])
}

pub fn get_path_name_test() {
  let env =
    Dict(
      dict.from_list([
        #("parent", Dict(dict.from_list([#("inner", String("hello"))]))),
      ]),
    )
  assert "hello" == pomade.get(env, ["parent", "inner"])
}
