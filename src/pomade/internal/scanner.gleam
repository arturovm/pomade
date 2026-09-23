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
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
import gleam/string

import splitter

type Lexer {
  Lexer(
    left_delimiter: String,
    right_delimiter: String,
    free_form_splitter: splitter.Splitter,
    whitespace_splitter: splitter.Splitter,
    tag_start_splitter: splitter.Splitter,
    triple_mustache_start_splitter: splitter.Splitter,
    identifier_splitter: splitter.Splitter,
    triple_mustache_end_splitter: splitter.Splitter,
    tag_end_splitter: splitter.Splitter,
  )
}

type ScannerState {
  Base
  FreeForm
  LineEnd
  TagStart
  TripleMustacheStart
  InsideTag
  TripleMustacheEnd
  TagEnd
  CustomizeDelimiters
  Comment
}

pub type Token {
  // general text
  TextLiteral(lexeme: String)
  WhitespaceLiteral(lexeme: String)
  NewlineLiteral(lexeme: String)
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
  //scan_loop(lexer, source, Base, [])
  scan_template(lexer, source)
}

fn new_lexer(left_delimiter: String, right_delimiter: String) -> Lexer {
  Lexer(
    left_delimiter: left_delimiter,
    right_delimiter: right_delimiter,
    free_form_splitter: splitter.new([" ", "\t", "\r\n", "\n", left_delimiter]),
    whitespace_splitter: splitter.new([" ", "\t"]),
    tag_start_splitter: splitter.new([left_delimiter]),
    triple_mustache_start_splitter: splitter.new([left_triple_mustache]),
    identifier_splitter: splitter.new([".", " ", right_delimiter]),
    triple_mustache_end_splitter: splitter.new([right_triple_mustache]),
    tag_end_splitter: splitter.new([right_delimiter]),
  )
}

fn scan_template(
  lexer: Lexer,
  source: String,
) -> Result(List(Token), LexicalError) {
  use #(tokens, tail) <- result.map(
    scan_repetition(
      lexer,
      source,
      is_one_of(lexer, [
        is_triple_mustache_start,
        is_tag_start,
        is_whitespace,
        is_text,
      ]),
      scan_top_level,
      [],
    ),
  )
  list.prepend(tokens, Eof)
  |> list.reverse()
}

fn scan_repetition(
  lexer: Lexer,
  source: String,
  predicate: fn(String) -> Bool,
  scanner: fn(Lexer, String, List(Token)) ->
    Result(#(Lexer, List(Token), String), LexicalError),
  acc: List(Token),
) -> Result(#(List(Token), String), LexicalError) {
  case predicate(source) {
    False -> Ok(#(acc, source))
    True -> {
      use #(lexer, tokens, tail) <- result.try(scanner(lexer, source, acc))
      scan_repetition(lexer, tail, predicate, scanner, tokens)
    }
  }
}

fn is_one_of(
  lexer: Lexer,
  predicates: List(fn(Lexer, String) -> Bool),
) -> fn(String) -> Bool {
  fn(source: String) {
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

fn scan_top_level(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case is_triple_mustache_start(lexer, source) {
    True -> scan_triple_mustache(lexer, source, acc)
    False ->
      case is_tag_start(lexer, source) {
        True -> scan_tag(lexer, source, acc)
        False ->
          case is_whitespace(lexer, source) {
            True -> scan_whitespace(lexer, source, acc)
            False ->
              case is_text(lexer, source) {
                True -> scan_text(lexer, source, acc)
                False -> {
                  echo "TOP LEVEL ERROR"
                  Error(UnexpectedCharacterError(
                    string.first(source) |> result.unwrap(""),
                  ))
                }
              }
          }
      }
  }
}

fn scan_triple_mustache(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(lexer, acc, tail) <- result.try(scan_left_triple_mustache(
    lexer,
    source,
    acc,
  ))
  let #(lexer, acc, tail) = scan_optional(lexer, tail, scan_whitespace, acc)
  use #(lexer, acc, tail) <- result.try(scan_name(lexer, tail, acc))
  let #(lexer, acc, tail) = scan_optional(lexer, tail, scan_whitespace, acc)
  use #(lexer, acc, tail) <- result.map(scan_right_triple_mustache(
    lexer,
    tail,
    acc,
  ))
  #(lexer, acc, tail)
}

fn scan_left_triple_mustache(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "{{{" <> tail -> Ok(#(lexer, list.prepend(acc, LeftTripleMustache), tail))
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_optional(
  lexer: Lexer,
  source: String,
  scanner: fn(Lexer, String, List(Token)) ->
    Result(#(Lexer, List(Token), String), LexicalError),
  acc: List(Token),
) -> #(Lexer, List(Token), String) {
  scanner(lexer, source, acc)
  |> result.unwrap(#(lexer, acc, source))
}

fn scan_name(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case is_dot(source) {
    True -> scan_dot(lexer, source, acc)
    False -> {
      use #(lexer, acc, tail) <- result.try(scan_identifier(lexer, source, acc))
      use #(acc, tail) <- result.map(scan_repetition(
        lexer,
        tail,
        is_dot,
        scan_dot_identifier,
        acc,
      ))
      #(lexer, acc, tail)
    }
  }
}

fn is_dot(source: String) -> Bool {
  string.starts_with(source, ".")
}

fn scan_dot(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "." <> tail -> Ok(#(lexer, list.prepend(acc, Dot), tail))
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_identifier(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(value, rest) <- result.map(read_identifier(
    source,
    lexer.identifier_splitter,
  ))
  #(lexer, list.prepend(acc, Identifier(value)), rest)
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
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(lexer, acc, tail) <- result.try(scan_dot(lexer, source, acc))
  use #(lexer, acc, tail) <- result.map(scan_identifier(lexer, tail, acc))
  #(lexer, acc, tail)
}

fn scan_right_triple_mustache(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "}}}" <> tail -> Ok(#(lexer, list.prepend(acc, RightTripleMustache), tail))
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_tag(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(lexer, acc, tail) <- result.try(scan_tag_start(lexer, source, acc))
  use #(new_lexer, acc, tail) <- result.try(scan_tag_content(lexer, tail, acc))
  use #(_lexer, acc, tail) <- result.map(scan_tag_end(lexer, tail, acc))
  #(new_lexer, acc, tail)
}

fn scan_tag_start(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case string.starts_with(source, lexer.left_delimiter) {
    True -> {
      let #(_, rest) = splitter.split_after(lexer.tag_start_splitter, source)
      Ok(#(lexer, list.prepend(acc, LeftDelimiter), rest))
    }
    False ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_tag_content(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case source {
    "!" <> _ -> scan_comment(lexer, source, acc)
    "=" <> _ -> scan_set_delimiters(lexer, source, acc)
    "&" <> _
    | "#" <> _
    | "/" <> _
    | ">" <> _
    | "^" <> _
    | "$" <> _
    | "<" <> _ -> scan_special(lexer, source, acc)
    _ -> scan_variable(lexer, source, acc)
  }
}

fn scan_comment(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let #(_, rest) = splitter.split_before(lexer.tag_end_splitter, source)
  Ok(#(lexer, list.prepend(acc, Ignored), rest))
}

fn scan_set_delimiters(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  Error(Unimplemented)
}

fn scan_special(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(acc, tail) <- result.try(scan_indicator(source, acc))
  let #(lexer, acc, tail) = scan_optional(lexer, tail, scan_whitespace, acc)
  use #(lexer, acc, tail) <- result.map(scan_name(lexer, tail, acc))
  let #(lexer, acc, tail) = scan_optional(lexer, tail, scan_whitespace, acc)
  #(lexer, acc, tail)
}

fn scan_indicator(
  source: String,
  acc: List(Token),
) -> Result(#(List(Token), String), LexicalError) {
  case source {
    "&" <> _ -> scan_single(source, RawVariableIndicator, acc)
    "#" <> _ -> scan_single(source, SectionIndicator, acc)
    "/" <> _ -> scan_single(source, ClosingIndicator, acc)
    "^" <> _ -> scan_single(source, InvertedSectionIndicator, acc)
    ">" <> _ -> scan_single(source, PartialIndicator, acc)
    "$" <> _ -> scan_single(source, BlockIndicator, acc)
    "<" <> _ -> scan_single(source, ParentIndicator, acc)
    _ -> Error(Unimplemented)
  }
}

fn scan_single(
  source: String,
  token: Token,
  acc: List(Token),
) -> Result(#(List(Token), String), LexicalError) {
  Ok(#(list.prepend(acc, token), string.drop_start(source, 1)))
}

fn scan_variable(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let #(lexer, acc, tail) = scan_optional(lexer, source, scan_whitespace, acc)
  use #(lexer, acc, tail) <- result.try(scan_name(lexer, tail, acc))
  let #(lexer, acc, tail) = scan_optional(lexer, tail, scan_whitespace, acc)
  Ok(#(lexer, acc, tail))
}

fn scan_tag_end(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  case string.starts_with(source, lexer.right_delimiter) {
    True -> {
      let #(_, rest) = splitter.split_after(lexer.tag_end_splitter, source)
      Ok(#(lexer, list.prepend(acc, RightDelimiter), rest))
    }
    False ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_whitespace(
  lexer: Lexer,
  source: String,
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  use #(ws, tail) <- result.map(consume_whitespace(source))
  let #(ws, tail) = whitespace_repetition(tail, ws)
  #(lexer, list.prepend(acc, WhitespaceLiteral(ws)), tail)
}

fn consume_whitespace(
  input: String,
) -> Result(#(String, String), LexicalError) {
  case input {
    " " as ws <> rest | "\t" as ws <> rest -> Ok(#(ws, rest))
    _ ->
      Error(UnexpectedCharacterError(string.first(input) |> result.unwrap("")))
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
  acc: List(Token),
) -> Result(#(Lexer, List(Token), String), LexicalError) {
  let #(text, rest) = splitter.split_before(lexer.free_form_splitter, source)
  Ok(#(lexer, list.prepend(acc, TextLiteral(text)), rest))
}

fn scan_loop(
  lexer: Lexer,
  source: String,
  mode: ScannerState,
  acc: List(Token),
) -> Result(List(Token), LexicalError) {
  case source {
    "" -> {
      let tokens = list.prepend(acc, Eof)
      Ok(list.reverse(tokens))
    }
    non_empty -> {
      use #(lexer, token, tail) <- result.try(scan_token(lexer, non_empty, mode))
      let tokens = case token {
        None -> acc
        Some(token) -> list.prepend(acc, token)
      }
      scan_loop(
        lexer,
        tail,
        transition_scanner_state(tail, lexer, mode),
        tokens,
      )
    }
  }
}

fn scan_token(
  lexer: Lexer,
  source: String,
  mode: ScannerState,
) -> Result(#(Lexer, Option(Token), String), LexicalError) {
  case mode {
    Base -> Ok(#(lexer, None, source))
    //FreeForm -> scan_with(source, lexer, scan_free_form)
    LineEnd -> scan_with(source, lexer, scan_line_end)
    //TagStart -> scan_with(source, lexer, scan_tag_start)
    TripleMustacheStart -> scan_with(source, lexer, scan_triple_mustache_start)
    InsideTag -> scan_with(source, lexer, scan_inside_tag)
    TripleMustacheEnd -> scan_with(source, lexer, scan_triple_mustache_end)
    //TagEnd -> scan_with(source, lexer, scan_tag_end)
    CustomizeDelimiters -> {
      use #(token, tail) <- result.map(scan_customize_delimiters(source, lexer))
      let assert SetDelimiters(left_delimiter, right_delimiter) = token
      let lexer = new_lexer(left_delimiter, right_delimiter)
      #(lexer, Some(token), tail)
    }
    //Comment -> scan_with(source, lexer, scan_comment)
    _ -> Error(Unimplemented)
  }
}

fn scan_with(
  source: String,
  lexer: Lexer,
  scanner: fn(String, Lexer) -> Result(#(Token, String), LexicalError),
) -> Result(#(Lexer, Option(Token), String), LexicalError) {
  use #(token, tail) <- result.map(scanner(source, lexer))
  #(lexer, Some(token), tail)
}

fn transition_scanner_state(
  source: String,
  lexer: Lexer,
  mode: ScannerState,
) -> ScannerState {
  case mode {
    Base -> transition_from_base(lexer, source)
    FreeForm
    | LineEnd
    | TagEnd
    | TripleMustacheEnd
    | CustomizeDelimiters
    | Comment -> Base
    TagStart -> InsideTag
    TripleMustacheStart -> InsideTag
    InsideTag ->
      case can_end_triple_mustache(lexer, source) {
        True -> TripleMustacheEnd
        False ->
          case string.starts_with(source, lexer.right_delimiter) {
            False -> InsideTag
            True -> TagEnd
          }
      }
  }
}

fn transition_from_base(lexer: Lexer, source: String) -> ScannerState {
  case source {
    "\r\n" <> _ | "\n" <> _ -> LineEnd
    _ ->
      case can_start_triple_mustache(lexer, source) {
        True -> TripleMustacheStart
        False ->
          case string.starts_with(source, lexer.left_delimiter) {
            False -> FreeForm
            True -> {
              case
                string.drop_start(source, string.length(lexer.left_delimiter))
              {
                "=" <> _ -> CustomizeDelimiters
                "!" <> _ -> Comment
                _ -> TagStart
              }
            }
          }
      }
  }
}

fn can_start_triple_mustache(lexer: Lexer, source: String) -> Bool {
  lexer.left_delimiter == default_left_delimiter
  && string.starts_with(source, left_triple_mustache)
}

fn can_end_triple_mustache(lexer: Lexer, source: String) -> Bool {
  lexer.right_delimiter == default_right_delimiter
  && string.starts_with(source, right_triple_mustache)
}

// fn scan_free_form(
//   source: String,
//   lexer: Lexer,
// ) -> Result(#(Token, String), LexicalError) {
//   let #(text, rest) = splitter.split_before(lexer.free_form_splitter, source)
//   case longest_whitespace_match(text, "") {
//     #("", _) -> {
//       let #(text, remainder) =
//         splitter.split_before(lexer.whitespace_splitter, text)
//       Ok(#(TextLiteral(text), remainder <> rest))
//     }
//     #(match, remainder) -> Ok(#(WhitespaceLiteral(match), remainder <> rest))
//   }
// }

fn scan_line_end(
  source: String,
  _lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  case source {
    "\r\n" as value <> rest | "\n" as value <> rest -> {
      Ok(#(NewlineLiteral(value), rest))
    }
    _ ->
      Error(UnexpectedCharacterError(string.first(source) |> result.unwrap("")))
  }
}

fn scan_triple_mustache_start(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(_, tail) =
    splitter.split_after(lexer.triple_mustache_start_splitter, source)
  Ok(#(LeftTripleMustache, tail))
}

fn scan_inside_tag(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  case source {
    // "&" <> _ -> scan_single(source, RawVariableIndicator)
    // "#" <> _ -> scan_single(source, SectionIndicator)
    // "/" <> _ -> scan_single(source, ClosingIndicator)
    // "^" <> _ -> scan_single(source, InvertedSectionIndicator)
    // ">" <> _ -> scan_single(source, PartialIndicator)
    // "$" <> _ -> scan_single(source, BlockIndicator)
    // "<" <> _ -> scan_single(source, ParentIndicator)
    // "." <> _ -> scan_single(source, Dot)
    _ -> Error(Unimplemented)
    //scan_identifier(source, lexer.identifier_splitter)
  }
}

fn scan_triple_mustache_end(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(_, tail) =
    splitter.split_after(lexer.triple_mustache_end_splitter, source)
  Ok(#(RightTripleMustache, tail))
}

fn scan_customize_delimiters(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let tag_start_length = string.length(lexer.left_delimiter)
  let tag_end_length = string.length(lexer.right_delimiter)
  use #(_, value, rest) <- result.try(read_tag_and_value(
    source,
    lexer.free_form_splitter,
    lexer.tag_end_splitter,
    tag_start_length + 1,
    tag_end_length + 1,
  ))
  use #(open, close) <- result.map(read_delimiter_value(value))
  #(SetDelimiters(open, close), rest)
}

fn read_tag_and_value(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  tag_start_length: Int,
  tag_end_length: Int,
) -> Result(#(String, String, String), LexicalError) {
  use #(tag, rest) <- result.map(read_tag(
    source,
    tag_start_splitter,
    tag_end_splitter,
  ))
  let value = read_value(tag, tag_start_length, tag_end_length)
  #(tag, value, rest)
}

fn read_tag(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
) -> Result(#(String, String), LexicalError) {
  let #(tag_start, rest) = splitter.split_after(tag_start_splitter, source)
  let #(tag_middle, tag_end, rest) = splitter.split(tag_end_splitter, rest)
  case string.is_empty(tag_end) && string.is_empty(rest) {
    True -> Error(UnterminatedTagError)
    False -> Ok(#(tag_start <> tag_middle <> tag_end, rest))
  }
}

fn read_value(tag: String, opening_length: Int, closing_length: Int) -> String {
  string.slice(
    tag,
    opening_length,
    string.length(tag) - { opening_length + closing_length },
  )
  |> string.trim()
}

fn read_delimiter_value(
  value: String,
) -> Result(#(String, String), LexicalError) {
  let assert Ok(re) = regexp.from_string("\\s+")
  case regexp.split(re, value) {
    [open, close] -> Ok(#(open, close))
    _ -> Error(MalformedSetDelimitersError)
  }
}
// fn scan_comment(
//   source: String,
//   lexer: Lexer,
// ) -> Result(#(Token, String), LexicalError) {
//   use #(_, rest) <- result.map(read_tag(
//     source,
//     lexer.free_form_splitter,
//     lexer.tag_end_splitter,
//   ))
//   #(Ignored, rest)
// }
