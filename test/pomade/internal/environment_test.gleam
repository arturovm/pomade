import gleam/dict

import pomade/internal/environment

pub fn empty_test() {
  assert "" == environment.get(environment.Dict(dict.new()), [])
}

pub fn not_found_test() {
  assert "" == environment.get(environment.Dict(dict.new()), ["non_existent"])
}

pub fn get_string_test() {
  let env =
    environment.Dict(dict.from_list([#("foo", environment.String("bar"))]))
  assert "bar" == environment.get(env, ["foo"])
}

pub fn get_int_test() {
  let env =
    environment.Dict(dict.from_list([#("number_value", environment.Int(2))]))
  assert "2" == environment.get(env, ["number_value"])
}

pub fn get_path_name_test() {
  let env =
    environment.Dict(
      dict.from_list([
        #(
          "parent",
          environment.Dict(
            dict.from_list([#("inner", environment.String("hello"))]),
          ),
        ),
      ]),
    )
  assert "hello" == environment.get(env, ["parent", "inner"])
}
