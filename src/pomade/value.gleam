import gleam/dict.{type Dict}

/// `Value` represents any of the possible types that can be passed as the
/// right-hand side of the dictionary used as input for Mustache templates
/// (what Mustache calls a "hash" in its official documentation).
pub type Value {
  Dict(Dict(String, Value))
  Int(Int)
  Float(Float)
  String(String)
  Bool(Bool)
  List(List(Value))
}

pub fn from_dict(value: Dict(String, Value)) -> Value {
  Dict(value)
}

pub fn from_int(value: Int) -> Value {
  Int(value)
}

pub fn from_float(value: Float) -> Value {
  Float(value)
}

pub fn from_string(value: String) -> Value {
  String(value)
}

pub fn from_bool(value: Bool) -> Value {
  Bool(value)
}

pub fn from_list(value: List(Value)) -> Value {
  List(value)
}
