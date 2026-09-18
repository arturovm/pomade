import pomade/internal/parser

pub type RuntimeError {
  RuntimeError
}

pub fn interpret(template: parser.Template) -> Result(String, RuntimeError) {
  let parser.Template(exprs) = template
  evaluate(exprs, "")
}

fn evaluate(
  exprs: List(parser.Expression),
  acc: String,
) -> Result(String, RuntimeError) {
  case exprs {
    [] -> Ok(acc)
    [parser.Text(value), ..tail] | [parser.Newline(value), ..tail] ->
      evaluate(tail, acc <> value)
    _ -> Error(RuntimeError)
  }
}
