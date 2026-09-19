import gleam/dict.{type Dict}
import gleam/int
import gleam/result

pub type Value {
  Dict(Dict(String, Value))
  Int(Int)
  String(String)
}

pub fn get(env: Value, path: List(String)) -> String {
  case get_path(env, path) {
    Ok(val) -> format(val)
    Error(Nil) -> ""
  }
}

fn get_path(env: Value, path: List(String)) -> Result(Value, Nil) {
  case path {
    [] -> Error(Nil)
    [key] -> get_in_val(env, key)
    [key, ..tail] -> {
      use val <- result.try(get_in_val(env, key))
      get_path(val, tail)
    }
  }
}

fn get_in_val(env: Value, key: String) -> Result(Value, Nil) {
  case env {
    Dict(dictionary) -> dict.get(dictionary, key)
    _ -> Error(Nil)
  }
}

fn format(val: Value) -> String {
  case val {
    Int(value) -> int.to_string(value)
    String(value) -> value
    _ -> ""
  }
}
