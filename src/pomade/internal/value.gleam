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
