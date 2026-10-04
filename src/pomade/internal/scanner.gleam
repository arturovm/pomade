//// Mustache lexical grammar:
////
//// template               -> {TRIPLE_MUSTACHE | tag | literal} {NEWLINE {TRIPLE_MUSTACHE | tag | literal}} ;
//// TRIPLE_MUSTACHE        -> "{{{" [WHITESPACE] name [WHITESPACE] "}}}" ;
//// literal                -> WHITESPACE | TEXT ;
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
//// TEXT                   -> {any - ("{{{" | left_delimiter | space | tab | NEWLINE)} ;
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
    // current source line
    line: Int,
    // current delimiter config
    left_delimiter: String,
    right_delimiter: String,
    // splitters
    // -- general text
    literal_splitter: splitter.Splitter,
    whitespace_splitter: splitter.Splitter,
    // -- identifiers
    identifier_splitter: splitter.Splitter,
    // -- tags
    tag_start_splitter: splitter.Splitter,
    tag_end_splitter: splitter.Splitter,
    // -- set delimiters
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
  case scan_top_level(lexer, source, []) {
    Ok(#(lexer, stream, tail)) ->
      case scan_newline_top_level(lexer, tail, stream) {
        Ok(#(lexer, stream, _)) ->
          Ok([Eof(lexer.line), ..stream] |> list.reverse())
        Error(error) -> Error(error)
      }
    Error(error) -> Error(error)
  }
}

fn scan_top_level(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case is_triple_mustache_start(lexer, source) {
    True ->
      case scan_triple_mustache(lexer, source, stream) {
        Ok(#(lexer, stream, tail)) -> scan_top_level(lexer, tail, stream)
        error -> error
      }
    False ->
      case is_tag_start(lexer, source) {
        True ->
          case scan_tag(lexer, source, stream) {
            Ok(#(lexer, stream, tail)) -> scan_top_level(lexer, tail, stream)
            error -> error
          }
        False ->
          case source {
            "\r\n" <> _ | "\n" <> _ | "" -> Ok(#(lexer, stream, source))
            _ -> {
              case scan_literal(lexer, source, stream) {
                Ok(#(lexer, stream, tail)) ->
                  scan_top_level(lexer, tail, stream)
                error -> error
              }
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
  #(lexer, [RawVariable(lexer.line, path), ..stream], tail)
}

fn read_name(
  lexer: Lexer,
  source: String,
) -> Result(#(List(String), String), LexicalError) {
  case source {
    "." <> rest -> Ok(#(["."], rest))
    _ -> {
      case read_identifier(lexer, source) {
        Ok(#(identifier, tail)) ->
          read_dot_identifier(lexer, tail, [identifier])
        Error(error) -> Error(error)
      }
    }
  }
}

fn read_identifier(
  lexer: Lexer,
  source: String,
) -> Result(#(String, String), LexicalError) {
  let #(value, rest) = splitter.split_before(lexer.identifier_splitter, source)
  case rest {
    "" -> Error(UnterminatedTagError(lexer.line))
    _ -> {
      case value {
        "" -> Error(MalformedIdentifierError(lexer.line))
        _ -> Ok(#(value, rest))
      }
    }
  }
}

fn read_dot_identifier(
  lexer: Lexer,
  source: String,
  acc: List(String),
) -> Result(#(List(String), String), LexicalError) {
  case source {
    "." <> tail -> {
      case read_identifier(lexer, tail) {
        Ok(#(identifier, tail)) ->
          read_dot_identifier(lexer, tail, [identifier, ..acc])
        Error(error) -> Error(error)
      }
    }
    tail -> Ok(#(list.reverse(acc), tail))
  }
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
  case splitter.split_after(lexer.tag_start_splitter, source) {
    #(_, "") -> Error(unexpected_character_error(lexer.line, source))
    #(_, rest) -> Ok(rest)
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
    #(_, rest) -> Ok(#(lexer, [Comment(lexer.line), ..stream], rest))
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
    [SetDelimiters(lexer.line, left_delimiter, right_delimiter), ..stream],
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
  #(lexer, [constructor(lexer.line, path), ..stream], tail)
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
  #(lexer, [constructor(lexer.line, identifier), ..stream], tail)
}

fn scan_variable(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let tail = discard_optional(lexer, source, read_whitespace)
  use #(path, tail) <- result.try(read_name(lexer, tail))
  let tail = discard_optional(lexer, tail, read_whitespace)
  Ok(#(lexer, [Variable(lexer.line, path), ..stream], tail))
}

fn discard_tag_end(
  lexer: Lexer,
  source: String,
) -> Result(String, LexicalError) {
  case splitter.split(lexer.tag_end_splitter, source) {
    #("", _, rest) -> Ok(rest)
    #(_, "", "") -> Error(UnterminatedTagError(lexer.line))
    _ -> Error(unexpected_character_error(lexer.line, source))
  }
}

fn scan_literal(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case splitter.split_before(lexer.literal_splitter, source) {
    #(literal, tail) ->
      case literal {
        "" -> Ok(#(lexer, stream, source))
        _ ->
          case is_blank(literal) {
            True ->
              Ok(#(lexer, [Whitespace(lexer.line, literal), ..stream], tail))
            False -> Ok(#(lexer, [Text(lexer.line, literal), ..stream], tail))
          }
      }
  }
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

fn scan_newline_top_level(
  lexer: Lexer,
  source: String,
  stream: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "\r\n" <> _ | "\n" <> _ -> {
      case scan_newline(lexer, source, stream) {
        Ok(#(lexer, stream, tail)) ->
          case scan_top_level(lexer, tail, stream) {
            Ok(#(lexer, stream, tail)) ->
              scan_newline_top_level(lexer, tail, stream)
            error -> error
          }
        error -> error
      }
    }
    _ -> Ok(#(lexer, stream, source))
  }
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
        [Newline(lexer.line, nl), ..stream],
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
    literal_splitter: splitter.new(["\r\n", "\n", left_delimiter]),
    whitespace_splitter: splitter.new([" ", "\t"]),
    tag_start_splitter: splitter.new([left_delimiter]),
    identifier_splitter: splitter.new([".", " ", right_delimiter]),
    tag_end_splitter: splitter.new([right_delimiter]),
    set_right_delimiter_splitter: splitter.new(["=", " ", "\t"]),
  )
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

fn is_triple_mustache_start(lexer: Lexer, source: String) -> Bool {
  case source {
    "{{{" <> _ if lexer.left_delimiter == default_left_delimiter -> True
    _ -> False
  }
}

fn is_tag_start(lexer: Lexer, source: String) -> Bool {
  string.starts_with(source, lexer.left_delimiter)
}

fn unexpected_character_error(line: Int, source: String) -> LexicalError {
  UnexpectedCharacterError(line, string.first(source) |> result.unwrap(""))
}

fn is_blank(lexeme: String) -> Bool {
  case lexeme {
    "" -> True
    " " <> tail | "\t" <> tail -> is_blank(tail)
    _ -> False
  }
}

// formatting

pub fn token_to_string(token: Token) -> String {
  case token {
    Text(_, _) -> "TEXT"
    Whitespace(_, _) -> "WHITESPACE"
    Newline(_, _) -> "NEWLINE"
    SectionStart(_, path) -> token_name_with_path("SECTION_START", path)
    InvertedSectionStart(_, path) ->
      token_name_with_path("INVERTED_SECTION_START", path)
    End(_, path) -> token_name_with_path("END_TAG", path)
    Partial(_, name) -> token_name_with_path("PARTIAL", [name])
    RawVariable(_, path) -> token_name_with_path("RAW_VARIABLE", path)
    Variable(_, path) -> token_name_with_path("VARIABLE", path)
    SetDelimiters(_, _, _) -> "SET_DELIMITERS"
    Comment(_) -> "COMMENT"
    Eof(_) -> "EOF"
  }
}

fn token_name_with_path(name: String, path: List(String)) -> String {
  name <> "(" <> string.join(path, ".") <> ")"
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
      "unexpected character: '" <> character <> "'"
  }
}
