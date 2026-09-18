import gleam/dict

import pomade/internal/environment

pub fn not_found_test() {
  let env = environment.new(dict.new())
  assert "" == environment.get(env, "non_existent")
}

pub fn get_string_test() {
  let env =
    environment.new(dict.from_list([#("foo", environment.String("bar"))]))
  assert "bar" == environment.get(env, "foo")
}
