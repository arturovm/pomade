//// Rewriting rules for Mustache:
////
//// _standalone_comment                          -> COMMENT NEWLINE            => empty ;
//// _standalone_comment_with_eof                 -> COMMENT EOF                => EOF ;
//// _standalone_comment_with_whitespace          -> WHITESPACE COMMENT NEWLINE => empty ;
//// _standalone_comment_with_whitespace_with_eof -> WHITESPACE COMMENT EOF     => EOF ;
//// _set_delimiters                              -> {any} SET_DELIMITERS {any} => {any} {any} ;
//// _comment                                     -> {any} COMMENT {any}        => {any} {any} ;
//// _standaline_partial                          -> PARTIAL NEWLINE            => PARTIAL ;
//// _standaline_partial_with_indendation         -> WHITESPACE PARTIAL NEWLINE => INDENTATION PARTIAL ;

import gleam/list

import pomade/internal/scanner

pub fn rewrite(tokens: List(scanner.Token)) -> List(scanner.Token) {
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
    [scanner.Newline(_, _) as nl, ..tail] -> #(
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
    [scanner.Comment(_), scanner.Newline(_, _)]
    | [scanner.Whitespace(_, _), scanner.Comment(_), scanner.Newline(_, _)] -> []
    // standalone comments with eof
    [scanner.Comment(_), scanner.Eof as eof]
    | [scanner.Whitespace(_, _), scanner.Comment(_), scanner.Eof as eof] -> [
      eof,
    ]
    // standalone section start with newline
    [scanner.SectionStart(_, _) as ss, scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.SectionStart(_, _) as ss,
        scanner.Newline(_, _),
      ] -> [
      ss,
    ]
    // standalone section start with eof
    [
      scanner.Whitespace(_, _),
      scanner.SectionStart(_, _) as ss,
      scanner.Eof as eof,
    ] -> [
      ss,
      eof,
    ]
    // standalone inverted section start with newline
    [scanner.InvertedSectionStart(_, _) as iss, scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.InvertedSectionStart(_, _) as iss,
        scanner.Newline(_, _),
      ] -> [
      iss,
    ]
    // standalone inverted section start with eof
    [
      scanner.Whitespace(_, _),
      scanner.InvertedSectionStart(_, _) as iss,
      scanner.Eof as eof,
    ] -> [iss, eof]
    // standalone end tag with newline
    [scanner.End(_, _) as end, scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.End(_, _) as end,
        scanner.Newline(_, _),
      ] -> [
      end,
    ]
    // standalone end tag with eof
    [scanner.Whitespace(_, _), scanner.End(_, _) as end, scanner.Eof as eof] -> [
      end, eof,
    ]
    // standalone set delimiters with newline
    [scanner.SetDelimiters(_, _, _), scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.SetDelimiters(_, _, _),
        scanner.Newline(_, _),
      ] -> []
    // standalone set delimiters with eof
    [scanner.SetDelimiters(_, _, _), scanner.Eof as eof]
    | [
        scanner.Whitespace(_, _),
        scanner.SetDelimiters(_, _, _),
        scanner.Eof as eof,
      ] -> [
      eof,
    ]
    // standalone partial with newline
    [scanner.Partial(_, _) as partial, scanner.Newline(_, _)] -> [partial]
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
    [scanner.Comment(_), ..tail] -> other_loop(tail, output)
    // set delimiters
    [scanner.SetDelimiters(_, _, _), ..tail] -> other_loop(tail, output)
    // continue
    [head, ..tail] -> other_loop(tail, list.prepend(output, head))
  }
}
