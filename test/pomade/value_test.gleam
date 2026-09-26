import gleam/dict

import pomade/value.{Dict, String}

pub fn from_test() {
  let assert Dict(dictionary) =
    value.from_dict(dict.from_list([#("Hello", value.from_string("Goodbye"))]))
  assert Ok(String("Goodbye")) == dict.get(dictionary, "Hello")
}
