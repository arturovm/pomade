import gleam/dict.{type Dict}
import gleam/option.{type Option, Some}

pub type Value {
  Dict(Dict(String, Option(Value)))
  Int(Int)
  Float(Float)
  String(String)
  Bool(Bool)
  List(List(Option(Value)))
}

pub fn from_dict(value: Dict(String, Option(Value))) -> Option(Value) {
  Some(Dict(value))
}

pub fn from_int(value: Int) -> Option(Value) {
  Some(Int(value))
}

pub fn from_float(value: Float) -> Option(Value) {
  Some(Float(value))
}

pub fn from_string(value: String) -> Option(Value) {
  Some(String(value))
}

pub fn from_bool(value: Bool) -> Option(Value) {
  Some(Bool(value))
}

pub fn from_list(value: List(Option(Value))) -> Option(Value) {
  Some(List(value))
}
