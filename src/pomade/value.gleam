import gleam/dict.{type Dict}

pub type Value {
  Dict(Dict(String, Value))
  Int(Int)
  String(String)
}
