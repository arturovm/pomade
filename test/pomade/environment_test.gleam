import gleam/dict
import gleam/option.{None, Some}

import pomade.{Dict, Environment, List, String}

pub fn empty_test() {
  assert "" == pomade.get_and_format(Environment(Dict(dict.new()), None), [])
}

pub fn not_found_test() {
  assert ""
    == pomade.get_and_format(Environment(Dict(dict.new()), None), [
      "non_existent",
    ])
}

pub fn get_string_test() {
  let env =
    Environment(
      pomade.from_dict(dict.from_list([#("foo", pomade.from_string("bar"))])),
      None,
    )
  assert "bar" == pomade.get_and_format(env, ["foo"])
}

pub fn get_int_test() {
  let env =
    Environment(
      pomade.from_dict(dict.from_list([#("number_value", pomade.from_int(2))])),
      None,
    )
  assert "2" == pomade.get_and_format(env, ["number_value"])
}

pub fn get_float_test() {
  let env =
    Environment(
      pomade.from_dict(
        dict.from_list([#("number_value", pomade.from_float(1.5))]),
      ),
      None,
    )
  assert "1.5" == pomade.get_and_format(env, ["number_value"])
}

pub fn get_bool_test() {
  let env =
    Environment(
      pomade.from_dict(
        dict.from_list([#("boolean_value", pomade.from_bool(True))]),
      ),
      None,
    )
  assert "True" == pomade.get_and_format(env, ["boolean_value"])
}

pub fn get_path_name_test() {
  let env =
    Environment(
      pomade.from_dict(
        dict.from_list([
          #(
            "parent",
            pomade.from_dict(
              dict.from_list([#("inner", pomade.from_string("hello"))]),
            ),
          ),
        ]),
      ),
      None,
    )
  assert "hello" == pomade.get_and_format(env, ["parent", "inner"])
}

pub fn get_self_test() {
  let env = Environment(String("hello"), None)
  assert "hello" == pomade.get_and_format(env, ["."])
}

pub fn get_value_test() {
  let env =
    Environment(
      pomade.from_dict(
        dict.from_list([
          #(
            "parent",
            pomade.from_dict(
              dict.from_list([#("inner", pomade.from_string("hello"))]),
            ),
          ),
          #("foo", pomade.from_string("goodbye")),
        ]),
      ),
      None,
    )
  assert Some(String("hello")) == pomade.get(env, ["parent", "inner"])
  assert Some(String("goodbye")) == pomade.get(env, ["foo"])
}

pub fn get_value_in_parent_test() {
  let parent_env =
    Environment(
      pomade.from_dict(
        dict.from_list([
          #("a", pomade.from_string("foo")),
          #("b", pomade.from_string("wrong")),
          #(
            "sec",
            pomade.from_dict(
              dict.from_list([
                #("b", pomade.from_string("bar")),
              ]),
            ),
          ),
          #(
            "c",
            pomade.from_dict(
              dict.from_list([
                #("d", pomade.from_string("baz")),
              ]),
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
          #("b", pomade.from_string("bar")),
        ]),
      ),
      Some(parent_env),
    )
  assert Some(String("foo")) == pomade.get(child_env, ["a"])
  assert Some(String("bar")) == pomade.get(child_env, ["b"])
  assert Some(String("baz")) == pomade.get(child_env, ["c", "d"])
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
