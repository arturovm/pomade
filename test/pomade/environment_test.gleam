import gleam/dict
import gleam/option.{None, Some}

import pomade/internal/environment.{Environment}
import pomade/internal/value.{Dict, List, String}

pub fn empty_test() {
  assert ""
    == environment.get_and_format(Environment(Dict(dict.new()), None, None), [])
}

pub fn not_found_test() {
  assert ""
    == environment.get_and_format(Environment(Dict(dict.new()), None, None), [
      "non_existent",
    ])
}

pub fn get_string_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("foo", value.String("bar"))])),
      None,
      None,
    )
  assert "bar" == environment.get_and_format(env, ["foo"])
}

pub fn get_int_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("number_value", value.Int(2))])),
      None,
      None,
    )
  assert "2" == environment.get_and_format(env, ["number_value"])
}

pub fn get_float_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("number_value", value.Float(1.5))])),
      None,
      None,
    )
  assert "1.5" == environment.get_and_format(env, ["number_value"])
}

pub fn get_bool_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("boolean_value", value.Bool(True))])),
      None,
      None,
    )
  assert "True" == environment.get_and_format(env, ["boolean_value"])
}

pub fn get_path_name_test() {
  let env =
    Environment(
      value.Dict(
        dict.from_list([
          #(
            "parent",
            value.Dict(dict.from_list([#("inner", value.String("hello"))])),
          ),
        ]),
      ),
      None,
      None,
    )
  assert "hello" == environment.get_and_format(env, ["parent", "inner"])
}

pub fn get_self_test() {
  let env = Environment(String("hello"), None, None)
  assert "hello" == environment.get_and_format(env, ["."])
}

pub fn get_value_test() {
  let env =
    Environment(
      value.Dict(
        dict.from_list([
          #(
            "parent",
            value.Dict(dict.from_list([#("inner", value.String("hello"))])),
          ),
          #("foo", value.String("goodbye")),
        ]),
      ),
      None,
      None,
    )
  assert Some(String("hello")) == environment.get(env, ["parent", "inner"])
  assert Some(String("goodbye")) == environment.get(env, ["foo"])
}

pub fn get_value_in_parent_test() {
  let parent_env =
    Environment(
      value.Dict(
        dict.from_list([
          #("a", value.String("foo")),
          #("b", value.String("wrong")),
          #(
            "sec",
            value.Dict(
              dict.from_list([
                #("b", value.String("bar")),
              ]),
            ),
          ),
          #(
            "c",
            value.Dict(
              dict.from_list([
                #("d", value.String("baz")),
              ]),
            ),
          ),
        ]),
      ),
      None,
      None,
    )
  let child_env =
    Environment(
      value.Dict(
        dict.from_list([
          #("b", value.String("bar")),
        ]),
      ),
      None,
      Some(parent_env),
    )
  assert Some(String("foo")) == environment.get(child_env, ["a"])
  assert Some(String("bar")) == environment.get(child_env, ["b"])
  assert Some(String("baz")) == environment.get(child_env, ["c", "d"])
}

pub fn get_list_test() {
  let env =
    Environment(
      value.Dict(
        dict.from_list([
          #("list_value", value.List([value.String("Hello")])),
        ]),
      ),
      None,
      None,
    )
  assert Some(List([String("Hello")])) == environment.get(env, ["list_value"])
}

pub fn get_partial_test() {
  let env =
    Environment(
      value.String("hello"),
      Some(dict.from_list([#("some_partial", "foo")])),
      None,
    )
  assert Some("foo") == environment.get_partial(env, "some_partial")
}
