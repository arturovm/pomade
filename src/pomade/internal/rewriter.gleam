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
  transform(tokens, [], indentation)
}

fn transform(
  tokens: List(scanner.Token),
  acc: List(Token),
  indentation: Option(String),
) {
  case tokens {
    [] -> list.reverse(acc)
    // standalone comments with newline
    [scanner.Comment(_), scanner.Newline(_, _), ..tail]
    | [
        scanner.Whitespace(_, _),
        scanner.Comment(_),
        scanner.Newline(_, _),
        ..tail
      ] -> transform(tail, acc, indentation)
    // standalone comments with eof
    [scanner.Comment(_), scanner.Eof(line), ..tail]
    | [scanner.Whitespace(_, _), scanner.Comment(_), scanner.Eof(line), ..tail] ->
      transform(tail, [Eof(line), ..acc], indentation)
    // standalone section start with newline
    [scanner.SectionStart(line, path), scanner.Newline(_, _), ..tail]
    | [
        scanner.Whitespace(_, _),
        scanner.SectionStart(line, path),
        scanner.Newline(_, _),
        ..tail
      ] -> transform(tail, [SectionStart(line, path), ..acc], indentation)
    // standalone section start with eof
    [
      scanner.Whitespace(_, _),
      scanner.SectionStart(line, path),
      scanner.Eof(_),
      ..tail
    ] ->
      transform(tail, [Eof(line), SectionStart(line, path), ..acc], indentation)
    // standalone inverted section start with newline
    [scanner.InvertedSectionStart(line, path), scanner.Newline(_, _), ..tail]
    | [
        scanner.Whitespace(_, _),
        scanner.InvertedSectionStart(line, path),
        scanner.Newline(_, _),
        ..tail
      ] ->
      transform(tail, [InvertedSectionStart(line, path), ..acc], indentation)
    // standalone inverted section start with eof
    [
      scanner.Whitespace(_, _),
      scanner.InvertedSectionStart(line, path),
      scanner.Eof(_),
      ..tail
    ] ->
      transform(
        tail,
        [Eof(line), InvertedSectionStart(line, path), ..acc],
        indentation,
      )
    // standalone end tag with newline
    [scanner.End(line, path), scanner.Newline(_, _), ..tail]
    | [
        scanner.Whitespace(_, _),
        scanner.End(line, path),
        scanner.Newline(_, _),
        ..tail
      ] -> transform(tail, [End(line, path), ..acc], indentation)
    // standalone end tag with eof
    [scanner.Whitespace(_, _), scanner.End(line, path), scanner.Eof(_), ..tail] ->
      transform(tail, [Eof(line), End(line, path), ..acc], indentation)
    // standalone set delimiters with newline
    [scanner.SetDelimiters(_, _, _), scanner.Newline(_, _), ..tail]
    | [
        scanner.Whitespace(_, _),
        scanner.SetDelimiters(_, _, _),
        scanner.Newline(_, _),
        ..tail
      ] -> transform(tail, acc, indentation)
    // standalone set delimiters with eof
    [scanner.SetDelimiters(_, _, _), scanner.Eof(line), ..tail]
    | [
        scanner.Whitespace(_, _),
        scanner.SetDelimiters(_, _, _),
        scanner.Eof(line),
        ..tail
      ] -> transform(tail, [Eof(line), ..acc], indentation)
    // standalone partial with newline
    [scanner.Partial(line, name), scanner.Newline(_, _), ..tail] ->
      transform(tail, [Partial(line, name), ..acc], indentation)
    // standalone partial with indentation
    [
      scanner.Whitespace(_, ws),
      scanner.Partial(line, name),
      scanner.Newline(_, _),
      ..tail
    ] -> {
      let total_indentation = case indentation {
        Some(indentation_value) -> indentation_value <> ws
        None -> ws
      }
      transform(
        tail,
        [Partial(line, name), Indentation(line, total_indentation), ..acc],
        indentation,
      )
    }
    // standalone partial with eof
    [
      scanner.Whitespace(_, ws),
      scanner.Partial(line, name),
      scanner.Eof(_),
      ..tail
    ] -> {
      let total_indentation = case indentation {
        Some(indentation_value) -> indentation_value <> ws
        None -> ws
      }
      transform(
        tail,
        [
          Eof(line),
          Partial(line, name),
          Indentation(line, total_indentation),
          ..acc
        ],
        indentation,
      )
    }
    // continue with in-line rules
    any -> {
      let acc = case indentation, any {
        _, [scanner.Eof(_)] -> acc
        Some(indentation_value), _ -> glom(0, indentation_value, acc)
        //[Literal(0, indentation_value), ..acc]
        _, _ -> acc
      }
      let #(acc, tail) = transform_other(any, acc)
      transform(tail, acc, indentation)
    }
  }
}

fn transform_other(
  input: List(scanner.Token),
  output: List(Token),
) -> #(List(Token), List(scanner.Token)) {
  case input {
    // base case
    [] -> #(output, input)
    // line ends, return
    [scanner.Newline(line, lexeme), ..tail] -> #(
      glom(line, lexeme, output),
      tail,
    )
    // comments
    [scanner.Comment(_), ..tail] -> transform_other(tail, output)
    // set delimiters
    [scanner.SetDelimiters(_, _, _), ..tail] -> transform_other(tail, output)
    // literals with glomming
    [scanner.Text(line, lexeme), ..tail]
    | [scanner.Whitespace(line, lexeme), ..tail] ->
      transform_other(tail, glom(line, lexeme, output))
    // other tokens
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

fn glom(line: Int, lexeme: String, output: List(Token)) -> List(Token) {
  case output {
    [Literal(_, literal), ..rest] -> [Literal(line, literal <> lexeme), ..rest]
    any -> [Literal(line, lexeme), ..any]
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
