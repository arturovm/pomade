//// Mustache lexical grammar:
////
//// template               -> {TRIPLE_MUSTACHE | tag | WHITESPACE | TEXT} {NEWLINE {TRIPLE_MUSTACHE | tag | WHITESPACE | TEXT}} ;
//// TRIPLE_MUSTACHE        -> "{{{" [WHITESPACE] name [WHITESPACE] "}}}" ;
//// tag                    -> COMMENT | SET_DELIMITERS | SECTION | INVERTED_SECTION | BLOCK | CLOSING_TAG | PARTIAL | PARENT | RAW_VARIABLE | VARIABLE ;
//// COMMENT                -> left_delimiter "!" {any - right_delimiter} right_delimiter ;
//// SET_DELIMITERS         -> left_delimiter [WHITESPACE] "=" user_defined_left_delimiter WHITESPACE user_defined_right_delimiter "=" [WHITESPACE] right_delimiter ;
//// SECTION_START          -> left_delimiter "#" [WHITESPACE] name [WHITESPACE] right_delimiter ;
//// INVERTED_SECTION_START -> left_delimiter "^" [WHITESPACE] name [WHITESPACE] right_delimiter ;
//// BLOCK_START            -> left_delimiter "$" [WHITESPACE] name [WHITESPACE] right_delimiter ;
//// PARENT_START           -> left_delimiter "<" [WHITESPACE] name [WHITESPACE] right_delimiter ;
//// END                    -> left_delimiter "/" [WHITESPACE] name [WHITESPACE] right_delimiter ;
//// PARTIAL                -> left_delimiter ">" [WHITESPACE] identifier [WHITESPACE] right_delimiter ;
//// RAW_VARIABLE           -> left_delimiter "&" [WHITESPACE] name [WHITESPACE] right_delimiter ;
//// VARIABLE               -> left_delimiter [WHITESPACE] name [WHITESPACE] right_delimiter ;
//// WHITESPACE             -> (" " | "\t") {" " | "\t"} ;
//// TEXT                   -> {any - (left_delimiter | space | tab | NEWLINE)} ;
//// NEWLINE                -> "\n" | "\r\n" ;
//// left_delimiter         -> "{{" | user_defined_left_delimiter ;
//// right_delimiter        -> "}}" | user_defined_right_delimiter ;
//// name                   -> "." | IDENTIFIER {"." IDENTIFIER} ;
//// identifier             -> (letter | digit | "-" | "_") {letter | digit | "-" | "_"} ;
//// letter                 -> "a"..."z" | "A"..."Z" ;
//// digit                  -> "0"..."9" ;

import gleam/int
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
  Text(line: Int, lexeme: String)
  Whitespace(line: Int, lexeme: String)
  Newline(line: Int, lexeme: String)
  // tags
  SectionStart(line: Int, path: List(String))
  InvertedSectionStart(line: Int, path: List(String))
  BlockStart(line: Int, path: List(String))
  ParentStart(line: Int, path: List(String))
  End(line: Int, path: List(String))
  Partial(line: Int, path: String)
  RawVariable(line: Int, path: List(String))
  Variable(line: Int, path: List(String))
  // special forms
  SetDelimiters(line: Int, tag_start: String, tag_end: String)
  Comment(line: Int)
  // eof
  Eof(line: Int)
}

/// `LexicalError` represents an error encountered during scanning.
pub type LexicalError {
  /// `MalformedIdentifierError` is returned when the scanner attempted to
  /// process an identifier inside a `{{tag}}`, but couldn't scan it
  /// appropriately.
  MalformedIdentifierError(line: Int)
  /// `UnterminatedTagError` is used to report that a `{{tag}}` does not have
  /// the expected right-hand side delimiter (`}}` in this example).
  UnterminatedTagError(line: Int)
  /// `MalformedSetDelimitersError` is returned when a set delimiters tag
  /// (e.g. `{{=<% %>=}}`) is encountered, but the scanner is not able to
  /// scan it appropriately.
  MalformedSetDelimitersError(line: Int)
  /// `UnexpectedCharacterError` is used to report that a character was found
  /// in a context where it was not expected.
  UnexpectedCharacterError(line: Int, character: String)
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
  use #(lexer, tokens, _) <- result.map(scan_repetition(
    lexer,
    tail,
    is_newline,
    scan_newline_top_level,
    tokens,
  ))
  list.prepend(tokens, Eof(lexer.line))
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
                False -> Error(unexpected_character_error(lexer.line, source))
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
  use tail <- result.try(discard(lexer, source, left_triple_mustache))
  let tail = discard_optional(lexer, tail, read_whitespace)
  use #(path, tail) <- result.try(read_name(lexer, tail))
  let tail = discard_optional(lexer, tail, read_whitespace)
  use tail <- result.map(discard(lexer, tail, right_triple_mustache))
  #(lexer, list.prepend(stream, RawVariable(lexer.line, path)), tail)
}

fn read_name(
  lexer: Lexer,
  source: String,
) -> Result(#(List(String), String), LexicalError) {
  case is_dot(lexer, source) {
    True -> {
      use tail <- result.map(discard(lexer, source, "."))
      #(["."], tail)
    }
    False -> {
      use #(identifier, tail) <- result.try(read_identifier(lexer, source))
      use #(path, tail) <- result.map(
        read_repetition(lexer, tail, is_dot, read_dot_identifier, [identifier]),
      )
      #(path, tail)
    }
  }
}

fn read_identifier(
  lexer: Lexer,
  source: String,
) -> Result(#(String, String), LexicalError) {
  let #(value, rest) = splitter.split_before(lexer.identifier_splitter, source)
  case string.is_empty(rest) {
    True -> Error(UnterminatedTagError(lexer.line))
    False -> {
      case string.is_empty(value) {
        True -> Error(MalformedIdentifierError(lexer.line))
        False -> Ok(#(value, rest))
      }
    }
  }
}

fn read_dot_identifier(
  lexer: Lexer,
  source: String,
) -> Result(#(String, String), LexicalError) {
  use tail <- result.try(discard(lexer, source, "."))
  use #(identifier, tail) <- result.map(read_identifier(lexer, tail))
  #(identifier, tail)
}

fn scan_tag(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use tail <- result.try(discard_tag_start(lexer, source))
  use #(new_lexer, stream, tail) <- result.try(scan_tag_content(
    lexer,
    tail,
    stream,
  ))
  use tail <- result.map(discard_tag_end(lexer, tail))
  #(new_lexer, stream, tail)
}

fn discard_tag_start(
  lexer: Lexer,
  source: String,
) -> Result(String, LexicalError) {
  case string.starts_with(source, lexer.left_delimiter) {
    True -> {
      let #(_, rest) = splitter.split_after(lexer.tag_start_splitter, source)
      Ok(rest)
    }
    False -> Error(unexpected_character_error(lexer.line, source))
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
    "#" <> tail -> scan_special(lexer, tail, stream, SectionStart)
    "^" <> tail -> scan_special(lexer, tail, stream, InvertedSectionStart)
    "$" <> tail -> scan_special(lexer, tail, stream, BlockStart)
    "<" <> tail -> scan_special(lexer, tail, stream, ParentStart)
    "/" <> tail -> scan_special(lexer, tail, stream, End)
    ">" <> tail -> scan_partial(lexer, tail, stream, Partial)
    "&" <> tail -> scan_special(lexer, tail, stream, RawVariable)
    _ -> scan_variable(lexer, source, stream)
  }
}

fn scan_comment(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case splitter.split_before(lexer.tag_end_splitter, source) {
    #(_, "") -> Error(UnterminatedTagError(lexer.line))
    #(_, rest) -> Ok(#(lexer, list.prepend(stream, Comment(lexer.line)), rest))
  }
}

fn scan_set_delimiters(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use tail <- result.try(discard(lexer, source, "="))
  let tail = discard_optional(lexer, tail, read_whitespace)
  use #(left_delimiter, tail) <- result.try(read_custom_left_delimiter_value(
    lexer,
    tail,
  ))
  use #(_, _, tail) <- result.try(consume_whitespace(lexer, tail))
  use #(right_delimiter, tail) <- result.try(read_custom_right_delimiter_value(
    lexer,
    tail,
  ))
  let tail = discard_optional(lexer, tail, read_whitespace)
  use tail <- result.map(discard(lexer, tail, "="))
  #(
    new_lexer(left_delimiter, right_delimiter),
    list.prepend(
      stream,
      SetDelimiters(lexer.line, left_delimiter, right_delimiter),
    ),
    tail,
  )
}

fn read_custom_left_delimiter_value(
  lexer: Lexer,
  source: String,
) -> Result(#(String, String), LexicalError) {
  case splitter.split_before(lexer.whitespace_splitter, source) {
    #("", _) -> Error(MalformedSetDelimitersError(lexer.line))
    #(left_delimiter, tail) -> Ok(#(left_delimiter, tail))
  }
}

fn read_custom_right_delimiter_value(
  lexer: Lexer,
  source: String,
) -> Result(#(String, String), LexicalError) {
  case splitter.split_before(lexer.set_right_delimiter_splitter, source) {
    #("", _) -> Error(MalformedSetDelimitersError(lexer.line))
    #(left_delimiter, tail) -> Ok(#(left_delimiter, tail))
  }
}

fn scan_special(
  lexer: Lexer,
  source: String,
  stream: List(Token),
  constructor: fn(Int, List(String)) -> Token,
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let tail = discard_optional(lexer, source, read_whitespace)
  use #(path, tail) <- result.map(read_name(lexer, tail))
  let tail = discard_optional(lexer, tail, read_whitespace)
  #(lexer, list.prepend(stream, constructor(lexer.line, path)), tail)
}

fn scan_partial(
  lexer: Lexer,
  source: String,
  stream: List(Token),
  constructor: fn(Int, String) -> Token,
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let tail = discard_optional(lexer, source, read_whitespace)
  use #(identifier, tail) <- result.map(read_identifier(lexer, tail))
  let tail = discard_optional(lexer, tail, read_whitespace)
  #(lexer, list.prepend(stream, constructor(lexer.line, identifier)), tail)
}

fn scan_variable(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let tail = discard_optional(lexer, source, read_whitespace)
  use #(path, tail) <- result.try(read_name(lexer, tail))
  let tail = discard_optional(lexer, tail, read_whitespace)
  Ok(#(lexer, list.prepend(stream, Variable(lexer.line, path)), tail))
}

fn discard_tag_end(
  lexer: Lexer,
  source: String,
) -> Result(String, LexicalError) {
  case string.starts_with(source, lexer.right_delimiter) {
    True -> {
      let #(_, rest) = splitter.split_after(lexer.tag_end_splitter, source)
      Ok(rest)
    }
    False -> Error(unexpected_character_error(lexer.line, source))
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
  use #(ws, tail) <- result.map(read_whitespace(lexer, source))
  #(lexer, Whitespace(lexer.line, ws), tail)
}

fn read_whitespace(
  lexer: Lexer,
  input: String,
) -> Result(#(String, String), LexicalError) {
  case input {
    " " as ws <> rest | "\t" as ws <> rest ->
      Ok(whitespace_repetition(rest, ws))
    _ -> Error(unexpected_character_error(lexer.line, input))
  }
}

fn whitespace_repetition(input: String, acc: String) -> #(String, String) {
  case input {
    " " as ws <> rest | "\t" as ws <> rest ->
      whitespace_repetition(rest, acc <> ws)
    _ -> #(acc, input)
  }
}

fn scan_text(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let #(text, rest) = splitter.split_before(lexer.free_form_splitter, source)
  Ok(#(lexer, list.prepend(stream, Text(lexer.line, text)), rest))
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
        list.prepend(stream, Newline(lexer.line, nl)),
        tail,
      ))
    _ -> Error(unexpected_character_error(lexer.line, source))
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
    set_right_delimiter_splitter: splitter.new(["=", " ", "\t"]),
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

fn read_repetition(
  lexer: Lexer,
  source: String,
  predicate: fn(Lexer, String) -> Bool,
  reader: fn(Lexer, String) -> Result(#(String, String), LexicalError),
  acc: List(String),
) -> Result(#(List(String), String), LexicalError) {
  case predicate(lexer, source) {
    False -> Ok(#(list.reverse(acc), source))
    True -> {
      use #(lexeme, tail) <- result.try(reader(lexer, source))
      read_repetition(lexer, tail, predicate, reader, list.prepend(acc, lexeme))
    }
  }
}

fn discard(
  lexer: Lexer,
  source: String,
  lexeme: String,
) -> Result(String, LexicalError) {
  case string.starts_with(source, lexeme) {
    True -> Ok(string.drop_start(source, string.length(lexeme)))
    False -> Error(unexpected_character_error(lexer.line, source))
  }
}

fn discard_optional(
  lexer: Lexer,
  source: String,
  reader: fn(Lexer, String) -> Result(#(String, String), LexicalError),
) -> String {
  case reader(lexer, source) {
    Ok(#(_, tail)) -> tail
    Error(_) -> source
  }
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

fn is_newline(_lexer: Lexer, source: String) -> Bool {
  case source {
    "\r\n" <> _ | "\n" <> _ -> True
    _ -> False
  }
}

fn unexpected_character_error(line: Int, source: String) -> LexicalError {
  UnexpectedCharacterError(line, string.first(source) |> result.unwrap(""))
}

// formatting

pub fn token_to_string(token: Token) -> String {
  "line "
  <> int.to_string(token.line)
  <> ": "
  <> case token {
    Text(_, _) -> "TEXT"
    Whitespace(_, _) -> "WHITESPACE"
    Newline(_, _) -> "NEWLINE"
    SectionStart(_, _) -> "SECTION_START"
    InvertedSectionStart(_, _) -> "INVERTED_SECTION_START"
    BlockStart(_, _) -> "BLOCK_START"
    ParentStart(_, _) -> "PARENT_START"
    End(_, _) -> "END_TAG"
    Partial(_, _) -> "PARTIAL"
    RawVariable(_, _) -> "RAW_VARIABLE"
    Variable(_, _) -> "VARIABLE"
    SetDelimiters(_, _, _) -> "SET_DELIMITERS"
    Comment(_) -> "COMMENT"
    Eof(_) -> "EOF"
  }
}

pub fn error_to_string(error: LexicalError) -> String {
  "line "
  <> int.to_string(error.line)
  <> ": "
  <> case error {
    MalformedIdentifierError(_) -> "malformed identifier"
    UnterminatedTagError(_) -> "unterminated tag"
    MalformedSetDelimitersError(_) -> "malformed set delimiters tag"
    UnexpectedCharacterError(_, character) ->
      "unexpected character: " <> character
  }
}
