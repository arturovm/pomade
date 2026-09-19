import gleam/dict
import gleam/option.{Some}

import pomade.{Dict, Int, String}

pub fn empty_test() {
  assert "" == pomade.get(Some(Dict(dict.new())), [])
}

pub fn not_found_test() {
  assert "" == pomade.get(Some(Dict(dict.new())), ["non_existent"])
}

pub fn get_string_test() {
  let env = Some(Dict(dict.from_list([#("foo", Some(String("bar")))])))
  assert "bar" == pomade.get(env, ["foo"])
}

pub fn get_int_test() {
  let env = Some(Dict(dict.from_list([#("number_value", Some(Int(2)))])))
  assert "2" == pomade.get(env, ["number_value"])
}

pub fn get_path_name_test() {
  let env =
    Some(
      Dict(
        dict.from_list([
          #(
            "parent",
            Some(Dict(dict.from_list([#("inner", Some(String("hello")))]))),
          ),
        ]),
      ),
    )
  assert "hello" == pomade.get(env, ["parent", "inner"])
}

pub fn get_self_test() {
  let env = Some(String("hello"))
  assert "hello" == pomade.get(env, ["."])
}
