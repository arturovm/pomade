import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}

import houdini

import pomade/value.{type Value, Bool, Dict, Float, Int, String}

pub type Environment {
  Environment(
    value: Value,
    partials: Option(Dict(String, String)),
    parent: Option(Environment),
  )
}

pub fn get_and_format(env: Environment, path: List(String)) -> String {
  get_and_format_raw(env, path) |> houdini.escape()
}

pub fn get_and_format_raw(env: Environment, path: List(String)) -> String {
  get(env, path) |> format()
}

pub fn get(env: Environment, path: List(String)) -> Option(Value) {
  case find_path_root_in_stack(env, path) {
    // if path was single-segment, return value found
    Some(#(val, [])) -> Some(val)
    // otherwise, there are more path segments to traverse, continue
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
        // found path root in this environment, return
        Some(found) -> Some(#(found, tail))
        None ->
          case env.parent {
            // environment has a parent, attempt lookup further up in stack
            Some(parent) -> find_path_root_in_stack(parent, path)
            None -> None
          }
      }
    [] -> None
  }
}

fn get_with_path(val: Value, path: List(String)) -> Option(Value) {
  case path {
    [] -> None
    // attempt final key lookup in current value, provided it's a dictionary
    [key] -> get_in_val(val, key)
    [key, ..tail] -> {
      // resolve next value in path
      use val <- option.then(get_in_val(val, key))
      // continue resolution on that value with remaining segments
      get_with_path(val, tail)
    }
  }
}

fn get_in_val(val: Value, key: String) -> Option(Value) {
  case key {
    // path refers to itself, return current value
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

pub fn get_partial(env: Environment, path: List(String)) -> Option(String) {
  option.then(env.partials, get_partial_with_path(_, path))
}

pub fn get_partial_with_path(
  partials: Dict(String, String),
  path: List(String),
) -> Option(String) {
  case path {
    [] -> None
    [key, ..] -> {
      dict.get(partials, key) |> option.from_result()
    }
  }
}
