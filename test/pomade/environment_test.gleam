import gleam/dict
import gleam/option.{None, Some}

import pomade/internal/environment.{Environment}
import pomade/internal/value.{Dict, List, String}

pub fn empty_test() {
  assert ""
    == environment.get_and_format(
      Environment(Dict(dict.new()), dict.new(), None),
      [],
    )
}

pub fn not_found_test() {
  assert ""
    == environment.get_and_format(
      Environment(Dict(dict.new()), dict.new(), None),
      [
        "non_existent",
      ],
    )
}

pub fn get_string_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("foo", value.String("bar"))])),
      dict.new(),
      None,
    )
  assert "bar" == environment.get_and_format(env, ["foo"])
}

pub fn get_int_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("number_value", value.Int(2))])),
      dict.new(),
      None,
    )
  assert "2" == environment.get_and_format(env, ["number_value"])
}

pub fn get_float_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("number_value", value.Float(1.5))])),
      dict.new(),
      None,
    )
  assert "1.5" == environment.get_and_format(env, ["number_value"])
}

pub fn get_bool_test() {
  let env =
    Environment(
      value.Dict(dict.from_list([#("boolean_value", value.Bool(True))])),
      dict.new(),
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
      dict.new(),
      None,
    )
  assert "hello" == environment.get_and_format(env, ["parent", "inner"])
}

pub fn get_self_test() {
  let env = Environment(String("hello"), dict.new(), None)
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
      dict.new(),
      None,
    )
  assert Ok(String("hello")) == environment.get(env, ["parent", "inner"])
  assert Ok(String("goodbye")) == environment.get(env, ["foo"])
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
      dict.new(),
      None,
    )
  let child_env =
    Environment(
      value.Dict(
        dict.from_list([
          #("b", value.String("bar")),
        ]),
      ),
      dict.new(),
      Some(parent_env),
    )
  assert Ok(String("foo")) == environment.get(child_env, ["a"])
  assert Ok(String("bar")) == environment.get(child_env, ["b"])
  assert Ok(String("baz")) == environment.get(child_env, ["c", "d"])
}

pub fn get_list_test() {
  let env =
    Environment(
      value.Dict(
        dict.from_list([
          #("list_value", value.List([value.String("Hello")])),
        ]),
      ),
      dict.new(),
      None,
    )
  assert Ok(List([String("Hello")])) == environment.get(env, ["list_value"])
}

pub fn get_partial_test() {
  let env =
    Environment(
      value.String("hello"),
      dict.from_list([#("some_partial", "foo")]),
      None,
    )
  assert Ok("foo") == environment.get_partial(env, "some_partial")
}
