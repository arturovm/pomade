//// Rewrite rules for Mustache:
////
//// _standalone_comment                  -> [WHITESPACE] COMMENT NEWLINE => empty ;
//// _standalone_comment_with_eof         -> [WHITESPACE] COMMENT EOF     => EOF ;
//// _standaline_partial                  -> PARTIAL NEWLINE              => PARTIAL ;
//// _standaline_partial_with_indendation -> WHITESPACE PARTIAL NEWLINE   => INDENTATION PARTIAL ;
//// _set_delimiters                      -> {any} SET_DELIMITERS {any}   => {any} {any} ;
//// _comment                             -> {any} COMMENT {any}          => {any} {any} ;

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import pomade/internal/scanner

pub type Token {
  // general text
  Literal(line: Int, lexeme: String)
  // tags
  SectionStart(line: Int, path: List(String))
  InvertedSectionStart(line: Int, path: List(String))
  End(line: Int, path: List(String))
  Partial(line: Int, path: String)
  RawVariable(line: Int, path: List(String))
  Variable(line: Int, path: List(String))
  // eof
  Eof(line: Int)
  // synthetic tokens
  Indentation(line: Int, lexeme: String)
}

pub type LayoutError {
  UnexpectedToken(scanner.Token)
}

pub fn rewrite(
  tokens: List(scanner.Token),
  indentation: Option(String),
) -> List(Token) {
  split_lines(tokens, [])
  |> list.flat_map(fn(line) { line |> transform() |> indent(indentation) })
  |> list.fold([], glom)
}

fn split_lines(
  tokens: List(scanner.Token),
  lines: List(List(scanner.Token)),
) -> List(List(scanner.Token)) {
  case tokens {
    [] -> list.reverse(lines)
    any -> {
      let #(next_line, tail) = next_line(any, [])
      split_lines(tail, [next_line, ..lines])
    }
  }
}

fn next_line(
  tokens: List(scanner.Token),
  line: List(scanner.Token),
) -> #(List(scanner.Token), List(scanner.Token)) {
  case tokens {
    [] -> #(list.reverse(line), tokens)
    [scanner.Newline(_, _) as nl, ..tail] -> #(
      [nl, ..line] |> list.reverse(),
      tail,
    )
    [any, ..tail] -> next_line(tail, [any, ..line])
  }
}

fn transform(line: List(scanner.Token)) -> List(Token) {
  case line {
    // standalone comments with newline
    [scanner.Comment(_), scanner.Newline(_, _)]
    | [scanner.Whitespace(_, _), scanner.Comment(_), scanner.Newline(_, _)] -> []
    // standalone comments with eof
    [scanner.Comment(_), scanner.Eof(line)]
    | [scanner.Whitespace(_, _), scanner.Comment(_), scanner.Eof(line)] -> [
      Eof(line),
    ]
    // standalone section start with newline
    [scanner.SectionStart(line, path), scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.SectionStart(line, path),
        scanner.Newline(_, _),
      ] -> [
      SectionStart(line, path),
    ]
    // standalone section start with eof
    [scanner.Whitespace(_, _), scanner.SectionStart(line, path), scanner.Eof(_)] -> [
      SectionStart(line, path),
      Eof(line),
    ]
    // standalone inverted section start with newline
    [scanner.InvertedSectionStart(line, path), scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.InvertedSectionStart(line, path),
        scanner.Newline(_, _),
      ] -> [
      InvertedSectionStart(line, path),
    ]
    // standalone inverted section start with eof
    [
      scanner.Whitespace(_, _),
      scanner.InvertedSectionStart(line, path),
      scanner.Eof(_),
    ] -> [InvertedSectionStart(line, path), Eof(line)]
    // standalone end tag with newline
    [scanner.End(line, path), scanner.Newline(_, _)]
    | [scanner.Whitespace(_, _), scanner.End(line, path), scanner.Newline(_, _)] -> [
      End(line, path),
    ]
    // standalone end tag with eof
    [scanner.Whitespace(_, _), scanner.End(line, path), scanner.Eof(_)] -> [
      End(line, path),
      Eof(line),
    ]
    // standalone set delimiters with newline
    [scanner.SetDelimiters(_, _, _), scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.SetDelimiters(_, _, _),
        scanner.Newline(_, _),
      ] -> []
    // standalone set delimiters with eof
    [scanner.SetDelimiters(_, _, _), scanner.Eof(line)]
    | [
        scanner.Whitespace(_, _),
        scanner.SetDelimiters(_, _, _),
        scanner.Eof(line),
      ] -> [
      Eof(line),
    ]
    // standalone partial with newline
    [scanner.Partial(line, name), scanner.Newline(_, _)] -> [
      Partial(line, name),
    ]
    // standalone partial with indentation
    [
      scanner.Whitespace(_, _) as ws,
      scanner.Partial(line, name),
      scanner.Newline(_, _),
    ] -> [Indentation(ws.line, ws.lexeme), Partial(line, name)]
    // standalone partial with eof
    [scanner.Whitespace(_, ws), scanner.Partial(line, name), scanner.Eof(_)] -> [
      Indentation(line, ws),
      Partial(line, name),
      Eof(line),
    ]
    // continue with in-line rules
    any -> transform_other(any, [])
  }
}

fn transform_other(
  input: List(scanner.Token),
  output: List(Token),
) -> List(Token) {
  case input {
    // base case
    [] -> list.reverse(output)
    // comments
    [scanner.Comment(_), ..tail] -> transform_other(tail, output)
    // set delimiters
    [scanner.SetDelimiters(_, _, _), ..tail] -> transform_other(tail, output)
    // other tokens
    [scanner.Text(line, lexeme), ..tail]
    | [scanner.Whitespace(line, lexeme), ..tail]
    | [scanner.Newline(line, lexeme), ..tail] ->
      transform_other(tail, [Literal(line, lexeme), ..output])
    [scanner.SectionStart(line, path), ..tail] ->
      transform_other(tail, [SectionStart(line, path), ..output])
    [scanner.InvertedSectionStart(line, path), ..tail] ->
      transform_other(tail, [InvertedSectionStart(line, path), ..output])
    [scanner.End(line, path), ..tail] ->
      transform_other(tail, [End(line, path), ..output])
    [scanner.Partial(line, path), ..tail] ->
      transform_other(tail, [Partial(line, path), ..output])
    [scanner.RawVariable(line, path), ..tail] ->
      transform_other(tail, [RawVariable(line, path), ..output])
    [scanner.Variable(line, path), ..tail] ->
      transform_other(tail, [Variable(line, path), ..output])
    [scanner.Eof(line), ..tail] -> transform_other(tail, [Eof(line), ..output])
  }
}

fn indent(line: List(Token), indentation: Option(String)) -> List(Token) {
  case indentation {
    None -> line
    Some(indentation_value) ->
      case line {
        []
        | [Eof(_)]
        | [SectionStart(_, _)]
        | [SectionStart(_, _), Eof(_)]
        | [InvertedSectionStart(_, _)]
        | [InvertedSectionStart(_, _), Eof(_)]
        | [End(_, _)]
        | [End(_, _), Eof(_)] -> line
        [Indentation(line, ws), ..tail] -> [
          Indentation(line, ws <> indentation_value),
          ..tail
        ]
        [Partial(_, _)] | [Partial(_, _), Eof(_)] -> [
          Indentation(0, indentation_value),
          ..line
        ]
        any -> [Literal(0, indentation_value), ..any]
      }
  }
}

fn glom(acc: List(Token), next: Token) -> List(Token) {
  case next {
    Literal(line, literal) -> {
      case acc {
        [Literal(line, value), ..acc_tail] -> [
          Literal(line, value <> literal),
          ..acc_tail
        ]
        acc -> [Literal(line, literal), ..acc]
      }
    }
    Eof(_) as eof -> [eof, ..acc] |> list.reverse()
    any -> [any, ..acc]
  }
}

// formatting

pub fn token_to_string(token: Token) -> String {
  case token {
    Literal(_, _) -> "LITERAL"
    SectionStart(_, path) -> token_name_with_path("SECTION_START", path)
    InvertedSectionStart(_, path) ->
      token_name_with_path("INVERTED_SECTION_START", path)
    End(_, path) -> token_name_with_path("END_TAG", path)
    Partial(_, name) -> token_name_with_path("PARTIAL", [name])
    RawVariable(_, path) -> token_name_with_path("RAW_VARIABLE", path)
    Variable(_, path) -> token_name_with_path("VARIABLE", path)
    Indentation(_, _) -> "INDENTATION"
    Eof(_) -> "EOF"
  }
}

fn token_name_with_path(name: String, path: List(String)) -> String {
  name <> "(" <> string.join(path, ".") <> ")"
}
