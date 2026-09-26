import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}

import houdini

import pomade/value.{type Value, Bool, Dict, Float, Int, String}

pub type Environment {
  Environment(value: Value, parent: Option(Environment))
}

pub fn get_and_format(env: Environment, path: List(String)) -> String {
  get_and_format_raw(env, path) |> houdini.escape()
}

pub fn get_and_format_raw(env: Environment, path: List(String)) -> String {
  get(env, path) |> format()
}

pub fn get(env: Environment, path: List(String)) -> Option(Value) {
  case find_path_root_in_stack(env, path) {
    Some(#(val, [])) -> Some(val)
    Some(#(val, tail)) -> get_with_path(val, tail)
    None -> None
  }
}

fn find_path_root_in_stack(
  env: Environment,
  path: List(String),
) -> Option(#(Value, List(String))) {
  case path {
    [head, ..tail] ->
      case get_in_val(env.value, head) {
        Some(found) -> Some(#(found, tail))
        None ->
          case env.parent {
            Some(parent) -> find_path_root_in_stack(parent, path)
            None -> None
          }
      }
    [] -> None
  }
}

pub fn get_with_path(val: Value, path: List(String)) -> Option(Value) {
  case path {
    [] -> None
    [key] -> get_in_val(val, key)
    [key, ..tail] -> {
      use val <- option.then(get_in_val(val, key))
      get_with_path(val, tail)
    }
  }
}

fn get_in_val(val: Value, key: String) -> Option(Value) {
  case key {
    "." -> Some(val)
    any ->
      case val {
        Dict(dictionary) -> dict.get(dictionary, any) |> option.from_result()
        _ -> None
      }
  }
}

fn format(val: Option(Value)) -> String {
  case val {
    Some(some) ->
      case some {
        Int(value) -> int.to_string(value)
        Float(value) -> float.to_string(value)
        String(value) -> value
        Bool(value) -> bool.to_string(value)
        _ -> ""
      }
    None -> ""
  }
}
