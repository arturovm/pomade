//// Elision rules for Mustache:
////
//// _set_delimiters -> LEFT_DELIMITER SET_DELIMITERS RIGHT_DELIMITER ;

import gleam/list
import pomade/internal/scanner

pub fn filter(tokens: List(scanner.Token)) -> List(scanner.Token) {
  split_lines(tokens)
  |> list.map(elide)
  |> list.flatten()
}

fn split_lines(tokens: List(scanner.Token)) -> List(List(scanner.Token)) {
  lines_loop(tokens, [])
}

fn lines_loop(
  tokens: List(scanner.Token),
  lines: List(List(scanner.Token)),
) -> List(List(scanner.Token)) {
  case tokens {
    [] -> list.reverse(lines)
    any -> {
      let #(next_line, tail) = line(any)
      let lines = list.prepend(lines, next_line)
      lines_loop(tail, lines)
    }
  }
}

fn line(
  tokens: List(scanner.Token),
) -> #(List(scanner.Token), List(scanner.Token)) {
  line_loop(tokens, [])
}

fn line_loop(
  tokens: List(scanner.Token),
  line: List(scanner.Token),
) -> #(List(scanner.Token), List(scanner.Token)) {
  case tokens {
    [] -> #(list.reverse(line), tokens)
    [scanner.NewlineLiteral(_) as nl, ..tail] -> #(
      list.prepend(line, nl) |> list.reverse(),
      tail,
    )
    [any, ..tail] -> line_loop(tail, list.prepend(line, any))
  }
}

fn elide(line: List(scanner.Token)) -> List(scanner.Token) {
  elide_loop(line, [])
}

fn elide_loop(
  input: List(scanner.Token),
  output: List(scanner.Token),
) -> List(scanner.Token) {
  case input {
    [] -> list.reverse(output)
    [
      scanner.LeftDelimiter,
      scanner.SetDelimiters(_, _),
      scanner.RightDelimiter,
      ..tail
    ] -> elide_loop(tail, output)
    [
      scanner.WhitespaceLiteral(_),
      scanner.LeftDelimiter,
      scanner.Ignored,
      scanner.RightDelimiter,
      scanner.NewlineLiteral(_),
    ]
    | [
        scanner.WhitespaceLiteral(_),
        scanner.LeftDelimiter,
        scanner.Ignored,
        scanner.RightDelimiter,
      ] -> elide_loop([], output)
    [scanner.LeftDelimiter, scanner.Ignored, scanner.RightDelimiter, ..tail] ->
      elide_loop(tail, output)
    [head, ..tail] -> elide_loop(tail, list.prepend(output, head))
  }
}
