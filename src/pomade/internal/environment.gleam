import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}

import houdini

import pomade/internal/value.{type Value, Bool, Dict, Float, Int, String}

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
  case get(env, path) {
    Ok(val) -> format(val)
    _ -> ""
  }
}

pub fn get(env: Environment, path: List(String)) -> Result(Value, Nil) {
  case path {
    [] -> Error(Nil)
    [head, ..tail] ->
      case find_path_root_in_stack(env, head) {
        // traverse
        Ok(val) -> get_with_path(val, tail)
        error -> error
      }
  }
}

fn find_path_root_in_stack(
  env: Environment,
  key: String,
) -> Result(Value, Nil) {
  case get_in_val(env.value, key) {
    // found path root in this environment, return
    Ok(found) -> Ok(found)
    Error(Nil) ->
      case env.parent {
        // environment has a parent, attempt lookup further up in stack
        Some(parent) -> find_path_root_in_stack(parent, key)
        None -> Error(Nil)
      }
  }
}

fn get_with_path(val: Value, path: List(String)) -> Result(Value, Nil) {
  case path {
    [] -> Ok(val)
    [key, ..tail] -> {
      // resolve next value in path
      case get_in_val(val, key) {
        // continue resolution on that value with remaining segments
        Ok(next) -> get_with_path(next, tail)
        error -> error
      }
    }
  }
}

fn get_in_val(val: Value, key: String) -> Result(Value, Nil) {
  case key, val {
    // path refers to itself, return current value
    ".", _ -> Ok(val)
    _, Dict(dictionary) -> dict.get(dictionary, key)
    _, _ -> Error(Nil)
  }
}

fn format(val: Value) -> String {
  case val {
    Int(value) -> int.to_string(value)
    Float(value) -> float.to_string(value)
    String(value) -> value
    Bool(value) -> bool.to_string(value)
    _ -> ""
  }
}

pub fn get_partial(env: Environment, name: String) -> Option(String) {
  option.then(env.partials, fn(partials) {
    dict.get(partials, name) |> option.from_result()
  })
}
