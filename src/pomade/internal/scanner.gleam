//// Mustache lexical grammar:
////
//// template        -> {triple_mustache | tag | WHITESPACE | TEXT} {NEWLINE {triple_mustache | tag | WHITESPACE | TEXT}} ;
//// triple_mustache -> "{{{" [WHITESPACE] name [WHITESPACE] "}}}" ;
//// WHITESPACE      -> (space | tab) {space | tab} ;
//// space           -> " " ;
//// tab             -> "\t" ;
//// name            -> "." | IDENTIFIER {"." IDENTIFIER} ;
//// IDENTIFIER      -> (letter | digit | "-" | "_") {letter | digit | "-" | "_"} ;
//// letter          -> "a"..."z" | "A"..."Z" ;
//// digit           -> "0"..."9" ;
//// tag             -> left_delimiter (COMMENT | SET_DELIMITERS | special | variable) right_delimiter ;
//// LEFT_DELIMITER  -> "{{" | user_defined_left_delimiter ;
//// COMMENT         -> "!" any ;
//// SET_DELIMITERS  -> "=" user_defined_left_delimiter [WHITESPACE] user_defined_right_delimiter "="
//// special         -> indicator [WHITESPACE] name [WHITESPACE] ;
//// indicator       -> "&" | "#" | "/" | ">" | "^" | "$" | "<" ;
//// variable        -> [WHITESPACE] name [WHITESPACE] ;
//// RIGHT_DELIMITER -> "}}" | user_defined_right_delimiter ;
//// TEXT            -> {any - (left_delimiter | space | tab | NEWLINE)} ;
//// NEWLINE         -> "\n" | "\r\n" ;

import gleam/list
import gleam/result
import gleam/string

import splitter

type Lexer {
  Lexer(
    line: Int,
    left_delimiter: String,
    right_delimiter: String,
    free_form_splitter: splitter.Splitter,
    whitespace_splitter: splitter.Splitter,
    tag_start_splitter: splitter.Splitter,
    triple_mustache_start_splitter: splitter.Splitter,
    identifier_splitter: splitter.Splitter,
    triple_mustache_end_splitter: splitter.Splitter,
    tag_end_splitter: splitter.Splitter,
    set_right_delimiter_splitter: splitter.Splitter,
  )
}

pub type Token {
  // general text
  Text(lexeme: String)
  Whitespace(lexeme: String)
  Newline(lexeme: String)
  // tags
  LeftDelimiter
  LeftTripleMustache
  RawVariableIndicator
  SectionIndicator
  ClosingIndicator
  InvertedSectionIndicator
  PartialIndicator
  BlockIndicator
  ParentIndicator
  RightTripleMustache
  RightDelimiter
  // tag content
  Identifier(lexeme: String)
  Dot
  // special forms
  SetDelimiters(tag_start: String, tag_end: String)
  Ignored
  // eof
  Eof
}

/// `LexicalError` represents an error encountered during scanning.
pub type LexicalError {
  /// `MalformedIdentifierError` is returned when the scanner attempted to
  /// process an identifier inside a `{{tag}}`, but couldn't scan it
  /// appropriately.
  MalformedIdentifierError
  /// `UnterminatedTagError` is used to report that a `{{tag}}` does not have
  /// the expected right-hand side delimiter (`}}` in this example).
  UnterminatedTagError
  /// `MalformedSetDelimitersError` is returned when a set delimiters tag
  /// (e.g. `{{=<% %>=}}`) is encountered, but the scanner is not able to
  /// scan it appropriately.
  MalformedSetDelimitersError
  /// `UnexpectedCharacterError` is used to report that a character was found
  /// in a context where it was not expected.
  UnexpectedCharacterError(character: String)
  Unimplemented
}

const default_left_delimiter: String = "{{"

const default_right_delimiter: String = "}}"

const left_triple_mustache: String = "{{{"

const right_triple_mustache: String = "}}}"

pub fn scan(source: String) -> Result(List(Token), LexicalError) {
  let lexer = new_lexer(default_left_delimiter, default_right_delimiter)
  scan_template(lexer, source)
}

fn scan_template(
  lexer: Lexer,
  source: String,
) -> Result(List(Token), LexicalError) {
  use #(lexer, tokens, tail) <- result.try(
    scan_repetition(
      lexer,
      source,
      is_one_of([
        is_triple_mustache_start,
        is_tag_start,
        is_whitespace,
        is_text,
      ]),
      scan_top_level,
      [],
    ),
  )
  use #(_, tokens, _) <- result.map(scan_repetition(
    lexer,
    tail,
    is_newline,
    scan_newline_top_level,
    tokens,
  ))
  list.prepend(tokens, Eof)
  |> list.reverse()
}

fn scan_top_level(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case is_triple_mustache_start(lexer, source) {
    True -> scan_triple_mustache(lexer, source, stream)
    False ->
      case is_tag_start(lexer, source) {
        True -> scan_tag(lexer, source, stream)
        False ->
          case is_whitespace(lexer, source) {
            True -> scan_whitespace(lexer, source, stream)
            False ->
              case is_text(lexer, source) {
                True -> scan_text(lexer, source, stream)
                False ->
                  Error(UnexpectedCharacterError(
                    string.first(source) |> result.unwrap(""),
                  ))
              }
          }
      }
  }
}

fn scan_triple_mustache(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(lexer, stream, tail) <- result.try(scan_left_triple_mustache(
    lexer,
    source,
    stream,
  ))
  let tail = discard_optional(lexer, tail, consume_whitespace)
  use #(lexer, stream, tail) <- result.try(scan_name(lexer, tail, stream))
  let tail = discard_optional(lexer, tail, consume_whitespace)
  use #(lexer, stream, tail) <- result.map(scan_right_triple_mustache(
    lexer,
    tail,
    stream,
  ))
  #(lexer, stream, tail)
}

fn scan_left_triple_mustache(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "{{{" <> tail ->
      Ok(#(lexer, list.prepend(stream, LeftTripleMustache), tail))
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_name(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case is_dot(lexer, source) {
    True -> scan_dot(lexer, source, stream)
    False -> {
      use #(lexer, stream, tail) <- result.try(scan_identifier(
        lexer,
        source,
        stream,
      ))
      use #(lexer, stream, tail) <- result.map(scan_repetition(
        lexer,
        tail,
        is_dot,
        scan_dot_identifier,
        stream,
      ))
      #(lexer, stream, tail)
    }
  }
}

fn scan_dot(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "." <> tail -> Ok(#(lexer, list.prepend(stream, Dot), tail))
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_identifier(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(value, rest) <- result.map(read_identifier(
    source,
    lexer.identifier_splitter,
  ))
  #(lexer, list.prepend(stream, Identifier(value)), rest)
}

fn read_identifier(
  source: String,
  identifier_splitter: splitter.Splitter,
) -> Result(#(String, String), LexicalError) {
  let #(value, rest) = splitter.split_before(identifier_splitter, source)
  case string.is_empty(rest) {
    True -> Error(UnterminatedTagError)
    False -> {
      case string.is_empty(value) {
        True -> Error(MalformedIdentifierError)
        False -> Ok(#(value, rest))
      }
    }
  }
}

fn scan_dot_identifier(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(lexer, stream, tail) <- result.try(scan_dot(lexer, source, stream))
  use #(lexer, stream, tail) <- result.map(scan_identifier(lexer, tail, stream))
  #(lexer, stream, tail)
}

fn scan_right_triple_mustache(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "}}}" <> tail ->
      Ok(#(lexer, list.prepend(stream, RightTripleMustache), tail))
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_tag(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(lexer, stream, tail) <- result.try(scan_tag_start(lexer, source, stream))
  use #(new_lexer, stream, tail) <- result.try(scan_tag_content(
    lexer,
    tail,
    stream,
  ))
  use #(_, stream, tail) <- result.map(scan_tag_end(lexer, tail, stream))
  #(new_lexer, stream, tail)
}

fn scan_tag_start(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case string.starts_with(source, lexer.left_delimiter) {
    True -> {
      let #(_, rest) = splitter.split_after(lexer.tag_start_splitter, source)
      Ok(#(lexer, list.prepend(stream, LeftDelimiter), rest))
    }
    False ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_tag_content(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "!" <> _ -> scan_comment(lexer, source, stream)
    "=" <> _ -> scan_set_delimiters(lexer, source, stream)
    "&" <> _
    | "#" <> _
    | "/" <> _
    | ">" <> _
    | "^" <> _
    | "$" <> _
    | "<" <> _ -> scan_special(lexer, source, stream)
    _ -> scan_variable(lexer, source, stream)
  }
}

fn scan_comment(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case splitter.split_before(lexer.tag_end_splitter, source) {
    #(_, "") -> Error(UnterminatedTagError)
    #(_, rest) -> Ok(#(lexer, list.prepend(stream, Ignored), rest))
  }
}

fn scan_set_delimiters(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use tail <- result.try(discard_set_delimiters_indicator(source))
  use #(left_delimiter, tail) <- result.try(read_left_delimiter_value(
    lexer,
    tail,
  ))
  use #(_, _, tail) <- result.try(consume_whitespace(lexer, tail))
  use #(right_delimiter, tail) <- result.try(read_right_delimiter_value(
    lexer,
    tail,
  ))
  use tail <- result.map(discard_set_delimiters_indicator(tail))
  #(
    new_lexer(left_delimiter, right_delimiter),
    list.prepend(stream, SetDelimiters(left_delimiter, right_delimiter)),
    tail,
  )
}

fn discard_set_delimiters_indicator(
  source: String,
) -> Result(String, LexicalError) {
  case source {
    "=" <> tail -> Ok(tail)
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn read_left_delimiter_value(
  lexer: Lexer,
  source: String,
) -> Result(#(String, String), LexicalError) {
  case splitter.split_before(lexer.whitespace_splitter, source) {
    #("", _) -> Error(MalformedSetDelimitersError)
    #(left_delimiter, tail) -> Ok(#(left_delimiter, tail))
  }
}

fn read_right_delimiter_value(
  lexer: Lexer,
  source: String,
) -> Result(#(String, String), LexicalError) {
  case splitter.split_before(lexer.set_right_delimiter_splitter, source) {
    #("", _) -> Error(MalformedSetDelimitersError)
    #(left_delimiter, tail) -> Ok(#(left_delimiter, tail))
  }
}

fn scan_special(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(stream, tail) <- result.try(scan_indicator(source, stream))
  let tail = discard_optional(lexer, tail, consume_whitespace)
  use #(lexer, stream, tail) <- result.map(scan_name(lexer, tail, stream))
  let tail = discard_optional(lexer, tail, consume_whitespace)
  #(lexer, stream, tail)
}

fn scan_indicator(
  source: String,
  stream: List(Token),
) -> Result(#(List(Token), String), LexicalError) {
  case source {
    "&" <> _ -> scan_single(source, RawVariableIndicator, stream)
    "#" <> _ -> scan_single(source, SectionIndicator, stream)
    "/" <> _ -> scan_single(source, ClosingIndicator, stream)
    "^" <> _ -> scan_single(source, InvertedSectionIndicator, stream)
    ">" <> _ -> scan_single(source, PartialIndicator, stream)
    "$" <> _ -> scan_single(source, BlockIndicator, stream)
    "<" <> _ -> scan_single(source, ParentIndicator, stream)
    _ -> Error(Unimplemented)
  }
}

fn scan_variable(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let tail = discard_optional(lexer, source, consume_whitespace)
  use #(lexer, stream, tail) <- result.try(scan_name(lexer, tail, stream))
  let tail = discard_optional(lexer, tail, consume_whitespace)
  Ok(#(lexer, stream, tail))
}

fn scan_tag_end(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case string.starts_with(source, lexer.right_delimiter) {
    True -> {
      let #(_, rest) = splitter.split_after(lexer.tag_end_splitter, source)
      Ok(#(lexer, list.prepend(stream, RightDelimiter), rest))
    }
    False ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_whitespace(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(_, ws, tail) <- result.map(consume_whitespace(lexer, source))
  #(lexer, list.prepend(stream, ws), tail)
}

fn consume_whitespace(
  lexer: Lexer,
  source: String,
) -> Result(#(Lexer, Token, String), LexicalError) {
  use #(ws, tail) <- result.map(read_whitespace(source))
  let #(ws, tail) = whitespace_repetition(tail, ws)
  #(lexer, Whitespace(ws), tail)
}

fn read_whitespace(input: String) -> Result(#(String, String), LexicalError) {
  case input {
    " " as ws <> rest | "\t" as ws <> rest -> Ok(#(ws, rest))
    _ ->
      Error(UnexpectedCharacterError(string.first(input) |> result.unwrap("")))
  }
}

fn whitespace_repetition(input: String, stream: String) -> #(String, String) {
  case input {
    " " as ws <> rest | "\t" as ws <> rest ->
      whitespace_repetition(rest, stream <> ws)
    _ -> #(stream, input)
  }
}

fn scan_text(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let #(text, rest) = splitter.split_before(lexer.free_form_splitter, source)
  Ok(#(lexer, list.prepend(stream, Text(text)), rest))
}

fn is_newline(_lexer: Lexer, source: String) -> Bool {
  case source {
    "\r\n" <> _ | "\n" <> _ -> True
    _ -> False
  }
}

fn scan_newline_top_level(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(lexer, stream, tail) <- result.try(scan_newline(lexer, source, stream))
  use #(lexer, stream, tail) <- result.map(scan_repetition(
    lexer,
    tail,
    is_one_of([
      is_triple_mustache_start,
      is_tag_start,
      is_whitespace,
      is_text,
    ]),
    scan_top_level,
    stream,
  ))
  #(lexer, stream, tail)
}

fn scan_newline(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "\r\n" as nl <> tail | "\n" as nl <> tail ->
      Ok(#(
        Lexer(..lexer, line: lexer.line + 1),
        list.prepend(stream, Newline(nl)),
        tail,
      ))
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

// helpers

fn new_lexer(left_delimiter: String, right_delimiter: String) -> Lexer {
  Lexer(
    line: 1,
    left_delimiter: left_delimiter,
    right_delimiter: right_delimiter,
    free_form_splitter: splitter.new([" ", "\t", "\r\n", "\n", left_delimiter]),
    whitespace_splitter: splitter.new([" ", "\t"]),
    tag_start_splitter: splitter.new([left_delimiter]),
    triple_mustache_start_splitter: splitter.new([left_triple_mustache]),
    identifier_splitter: splitter.new([".", " ", right_delimiter]),
    triple_mustache_end_splitter: splitter.new([right_triple_mustache]),
    tag_end_splitter: splitter.new([right_delimiter]),
    set_right_delimiter_splitter: splitter.new(["="]),
  )
}

fn scan_repetition(
  lexer: Lexer,
  source: String,
  predicate: fn(Lexer, String) -> Bool,
  scanner: fn(Lexer, String, List(Token)) ->
    Result(#(Lexer, List(Token), String), LexicalError),
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case predicate(lexer, source) {
    False -> Ok(#(lexer, stream, source))
    True -> {
      use #(lexer, tokens, tail) <- result.try(scanner(lexer, source, stream))
      scan_repetition(lexer, tail, predicate, scanner, tokens)
    }
  }
}

fn discard_optional(
  lexer: Lexer,
  source: String,
  consumer: fn(Lexer, String) -> Result(#(Lexer, Token, String), LexicalError),
) -> String {
  case consumer(lexer, source) {
    Ok(#(_, _, tail)) -> tail
    Error(_) -> source
  }
}

fn scan_single(
  source: String,
  token: Token,
  stream: List(Token),
) -> Result(#(List(Token), String), LexicalError) {
  Ok(#(list.prepend(stream, token), string.drop_start(source, 1)))
}

fn is_one_of(
  predicates: List(fn(Lexer, String) -> Bool),
) -> fn(Lexer, String) -> Bool {
  fn(lexer: Lexer, source: String) {
    list.map(predicates, fn(p) { p(lexer, source) })
    |> list.fold(False, fn(acc, v) { v || acc })
  }
}

fn is_triple_mustache_start(lexer: Lexer, source: String) -> Bool {
  lexer.left_delimiter == default_left_delimiter
  && string.starts_with(source, left_triple_mustache)
}

fn is_tag_start(lexer: Lexer, source: String) -> Bool {
  string.starts_with(source, lexer.left_delimiter)
}

fn is_whitespace(_lexer: Lexer, source: String) -> Bool {
  case source {
    " " <> _ | "\t" <> _ -> True
    _ -> False
  }
}

fn is_text(lexer: Lexer, source: String) -> Bool {
  case is_tag_start(lexer, source) {
    True -> False
    False ->
      case source {
        "" | " " <> _ | "\t" <> _ | "\n" <> _ | "\r\n" <> _ -> False
        _ -> True
      }
  }
}

fn is_dot(_lexer: Lexer, source: String) -> Bool {
  string.starts_with(source, ".")
}
