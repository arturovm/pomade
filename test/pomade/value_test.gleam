import gleam/dict
import gleam/option.{Some}

import pomade/value.{Dict, String}

pub fn from_test() {
  let assert Some(Dict(dictionary)) =
    value.from_dict(dict.from_list([#("Hello", value.from_string("Goodbye"))]))
  assert Ok(Some(String("Goodbye"))) == dict.get(dictionary, "Hello")
}
