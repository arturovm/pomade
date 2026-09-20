import gleam/dict
import gleam/option.{None, Some}

import pomade.{Dict, Environment, List, String}

pub fn empty_test() {
  assert "" == pomade.get_and_format(Dict(dict.new()), [])
}

pub fn not_found_test() {
  assert "" == pomade.get_and_format(Dict(dict.new()), ["non_existent"])
}

pub fn get_string_test() {
  let env =
    pomade.from_dict(dict.from_list([#("foo", pomade.from_string("bar"))]))
  assert "bar" == pomade.get_and_format(env, ["foo"])
}

pub fn get_int_test() {
  let env =
    pomade.from_dict(dict.from_list([#("number_value", pomade.from_int(2))]))
  assert "2" == pomade.get_and_format(env, ["number_value"])
}

pub fn get_float_test() {
  let env =
    pomade.from_dict(
      dict.from_list([#("number_value", pomade.from_float(1.5))]),
    )
  assert "1.5" == pomade.get_and_format(env, ["number_value"])
}

pub fn get_bool_test() {
  let env =
    pomade.from_dict(
      dict.from_list([#("boolean_value", pomade.from_bool(True))]),
    )
  assert "True" == pomade.get_and_format(env, ["boolean_value"])
}

pub fn get_path_name_test() {
  let env =
    pomade.from_dict(
      dict.from_list([
        #(
          "parent",
          pomade.from_dict(
            dict.from_list([#("inner", pomade.from_string("hello"))]),
          ),
        ),
      ]),
    )
  assert "hello" == pomade.get_and_format(env, ["parent", "inner"])
}

pub fn get_self_test() {
  let env = String("hello")
  assert "hello" == pomade.get_and_format(env, ["."])
}

pub fn get_value_test() {
  let val =
    pomade.from_dict(
      dict.from_list([
        #(
          "parent",
          pomade.from_dict(
            dict.from_list([#("inner", pomade.from_string("hello"))]),
          ),
        ),
      ]),
    )
  let env = Environment(val, None)
  assert Some(String("hello")) == pomade.get(env, ["parent", "inner"])
}

pub fn get_value_in_parent_test() {
  let parent_env =
    Environment(
      pomade.from_dict(
        dict.from_list([
          #(
            "parent",
            pomade.from_dict(
              dict.from_list([#("foo", pomade.from_string("hello"))]),
            ),
          ),
        ]),
      ),
      None,
    )
  let child_env =
    Environment(
      pomade.from_dict(
        dict.from_list([
          #(
            "child",
            pomade.from_dict(
              dict.from_list([#("bar", pomade.from_string("goodbye"))]),
            ),
          ),
        ]),
      ),
      Some(parent_env),
    )
  assert Some(String("hello")) == pomade.get(child_env, ["parent", "foo"])
}

pub fn get_list_test() {
  let env =
    Environment(
      pomade.from_dict(
        dict.from_list([
          #("list_value", pomade.from_list([pomade.from_string("Hello")])),
        ]),
      ),
      None,
    )
  assert Some(List([String("Hello")])) == pomade.get(env, ["list_value"])
}
