//// Elision rules for Mustache:
////
//// _set_delimiters -> LEFT_DELIMITER SET_DELIMITERS RIGHT_DELIMITER ;

import gleam/list
import pomade/internal/scanner

pub fn filter(tokens: List(scanner.Token)) -> List(scanner.Token) {
  split_lines(tokens)
  |> elide(standalone)
  |> elide(other)
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
    [scanner.Newline(_) as nl, ..tail] -> #(
      list.prepend(line, nl) |> list.reverse(),
      tail,
    )
    [any, ..tail] -> line_loop(tail, list.prepend(line, any))
  }
}

fn elide(
  lines: List(List(scanner.Token)),
  with: fn(List(scanner.Token)) -> List(scanner.Token),
) -> List(List(scanner.Token)) {
  list.map(lines, with)
}

fn standalone(line: List(scanner.Token)) -> List(scanner.Token) {
  case line {
    // standalone comments with newline
    [
      scanner.LeftDelimiter,
      scanner.Ignored,
      scanner.RightDelimiter,
      scanner.Newline(_),
    ]
    | [
        scanner.Whitespace(_),
        scanner.LeftDelimiter,
        scanner.Ignored,
        scanner.RightDelimiter,
        scanner.Newline(_),
      ] -> []
    // standalone comments with eof
    [
      scanner.LeftDelimiter,
      scanner.Ignored,
      scanner.RightDelimiter,
      scanner.Eof,
    ]
    | [
        scanner.Whitespace(_),
        scanner.LeftDelimiter,
        scanner.Ignored,
        scanner.RightDelimiter,
        scanner.Eof,
      ] -> [scanner.Eof]
    // continue
    any -> any
  }
}

fn other(line: List(scanner.Token)) -> List(scanner.Token) {
  other_loop(line, [])
}

fn other_loop(
  input: List(scanner.Token),
  output: List(scanner.Token),
) -> List(scanner.Token) {
  case input {
    // base case
    [] -> list.reverse(output)
    // comments
    [scanner.LeftDelimiter, scanner.Ignored, scanner.RightDelimiter, ..tail] ->
      other_loop(tail, output)
    // set delimiters
    [
      scanner.LeftDelimiter,
      scanner.SetDelimiters(_, _),
      scanner.RightDelimiter,
      ..tail
    ] -> other_loop(tail, output)
    // continue
    [head, ..tail] -> other_loop(tail, list.prepend(output, head))
  }
}
