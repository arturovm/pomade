import gleam/dict
import gleam/option.{None, Some}

import pomade/value.{Dict, List, String}

import pomade/internal/environment.{Environment}

pub fn empty_test() {
  assert ""
    == environment.get_and_format(Environment(Dict(dict.new()), None), [])
}

pub fn not_found_test() {
  assert ""
    == environment.get_and_format(Environment(Dict(dict.new()), None), [
      "non_existent",
    ])
}

pub fn get_string_test() {
  let env =
    Environment(
      value.from_dict(dict.from_list([#("foo", value.from_string("bar"))])),
      None,
    )
  assert "bar" == environment.get_and_format(env, ["foo"])
}

pub fn get_int_test() {
  let env =
    Environment(
      value.from_dict(dict.from_list([#("number_value", value.from_int(2))])),
      None,
    )
  assert "2" == environment.get_and_format(env, ["number_value"])
}

pub fn get_float_test() {
  let env =
    Environment(
      value.from_dict(
        dict.from_list([#("number_value", value.from_float(1.5))]),
      ),
      None,
    )
  assert "1.5" == environment.get_and_format(env, ["number_value"])
}

pub fn get_bool_test() {
  let env =
    Environment(
      value.from_dict(
        dict.from_list([#("boolean_value", value.from_bool(True))]),
      ),
      None,
    )
  assert "True" == environment.get_and_format(env, ["boolean_value"])
}

pub fn get_path_name_test() {
  let env =
    Environment(
      value.from_dict(
        dict.from_list([
          #(
            "parent",
            value.from_dict(
              dict.from_list([#("inner", value.from_string("hello"))]),
            ),
          ),
        ]),
      ),
      None,
    )
  assert "hello" == environment.get_and_format(env, ["parent", "inner"])
}

pub fn get_self_test() {
  let env = Environment(String("hello"), None)
  assert "hello" == environment.get_and_format(env, ["."])
}

pub fn get_value_test() {
  let env =
    Environment(
      value.from_dict(
        dict.from_list([
          #(
            "parent",
            value.from_dict(
              dict.from_list([#("inner", value.from_string("hello"))]),
            ),
          ),
          #("foo", value.from_string("goodbye")),
        ]),
      ),
      None,
    )
  assert Some(String("hello")) == environment.get(env, ["parent", "inner"])
  assert Some(String("goodbye")) == environment.get(env, ["foo"])
}

pub fn get_value_in_parent_test() {
  let parent_env =
    Environment(
      value.from_dict(
        dict.from_list([
          #("a", value.from_string("foo")),
          #("b", value.from_string("wrong")),
          #(
            "sec",
            value.from_dict(
              dict.from_list([
                #("b", value.from_string("bar")),
              ]),
            ),
          ),
          #(
            "c",
            value.from_dict(
              dict.from_list([
                #("d", value.from_string("baz")),
              ]),
            ),
          ),
        ]),
      ),
      None,
    )
  let child_env =
    Environment(
      value.from_dict(
        dict.from_list([
          #("b", value.from_string("bar")),
        ]),
      ),
      Some(parent_env),
    )
  assert Some(String("foo")) == environment.get(child_env, ["a"])
  assert Some(String("bar")) == environment.get(child_env, ["b"])
  assert Some(String("baz")) == environment.get(child_env, ["c", "d"])
}

pub fn get_list_test() {
  let env =
    Environment(
      value.from_dict(
        dict.from_list([
          #("list_value", value.from_list([value.from_string("Hello")])),
        ]),
      ),
      None,
    )
  assert Some(List([String("Hello")])) == environment.get(env, ["list_value"])
}
