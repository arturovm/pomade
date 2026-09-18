import gleam/dict
import gleam/int

pub opaque type Environment {
  Environment(inner: dict.Dict(String, Value))
}

pub type Value {
  Int(Int)
  String(String)
}

pub fn new(data: dict.Dict(String, Value)) -> Environment {
  Environment(data)
}

pub fn get(env: Environment, key: String) -> String {
  case dict.get(env.inner, key) {
    Error(Nil) -> ""
    Ok(val) -> format(val)
  }
}

fn format(val: Value) -> String {
  case val {
    Int(value) -> int.to_string(value)
    String(value) -> value
  }
}
