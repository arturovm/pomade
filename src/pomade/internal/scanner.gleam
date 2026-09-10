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
    tag_start_splitter: splitter.Splitter,
    triple_mustache_start_splitter: splitter.Splitter,
    identifier_splitter: splitter.Splitter,
    triple_mustache_end_splitter: splitter.Splitter,
    tag_end_splitter: splitter.Splitter,
  )
}

type Mode {
  Base
  FreeForm
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
  Text(source_length: Int, value: String)
  // tags
  LeftDelimiter(source_length: Int)
  LeftTripleMustache(source_length: Int)
  RawVariableIndicator(source_length: Int)
  SectionIndicator(source_length: Int)
  ClosingIndicator(source_length: Int)
  InvertedSectionIndicator(source_length: Int)
  PartialIndicator(source_length: Int)
  BlockIndicator(source_length: Int)
  ParentIndicator(source_length: Int)
  RightTripleMustache(source_length: Int)
  RightDelimiter(source_length: Int)
  // tag content
  Identifier(source_length: Int, value: String)
  Dot(source_length: Int)
  // special forms
  SetDelimiters(source_length: Int, tag_start: String, tag_end: String)
  Ignored(source_length: Int)
}

pub type LexicalError {
  MalformedIdentifierError
  UnterminatedTagError
  MalformedSetDelimitersError
}

const default_left_delimiter: String = "{{"

const default_right_delimiter: String = "}}"

const left_triple_mustache: String = "{{{"

const right_triple_mustache: String = "}}}"

pub fn scan(source: String) -> Result(List(Token), LexicalError) {
  let lexer = new_lexer(default_left_delimiter, default_right_delimiter)
  scan_loop(lexer, source, Base, [])
}

fn new_lexer(left_delimiter: String, right_delimiter: String) -> Lexer {
  Lexer(
    left_delimiter,
    right_delimiter,
    splitter.new([left_delimiter]),
    splitter.new([left_triple_mustache]),
    splitter.new([".", right_delimiter]),
    splitter.new([right_triple_mustache]),
    splitter.new([right_delimiter]),
  )
}

fn scan_loop(
  lexer: Lexer,
  source: String,
  mode: Mode,
  tokens: List(Token),
) -> Result(List(Token), LexicalError) {
  case source {
    "" -> Ok(list.reverse(tokens))
    non_empty -> {
      use #(lexer, token, tail) <- result.try(scan_token(lexer, non_empty, mode))
      let tokens = case token {
        None -> tokens
        Some(token) -> list.prepend(tokens, token)
      }
      scan_loop(lexer, tail, next_mode(tail, lexer, mode), tokens)
    }
  }
}

fn scan_token(
  lexer: Lexer,
  source: String,
  mode: Mode,
) -> Result(#(Lexer, Option(Token), String), LexicalError) {
  case mode {
    Base -> Ok(#(lexer, None, source))
    FreeForm -> scan_with(source, lexer, scan_free_form)
    TagStart -> scan_with(source, lexer, scan_tag_start)
    TripleMustacheStart -> scan_with(source, lexer, scan_triple_mustache_start)
    InsideTag -> scan_with(source, lexer, scan_inside_tag)
    TripleMustacheEnd -> scan_with(source, lexer, scan_triple_mustache_end)
    TagEnd -> scan_with(source, lexer, scan_tag_end)
    CustomizeDelimiters -> {
      use #(token, tail) <- result.map(scan_customize_delimiters(source, lexer))
      let assert SetDelimiters(_, left_delimiter, right_delimiter) = token
      let lexer = new_lexer(left_delimiter, right_delimiter)
      #(lexer, Some(token), tail)
    }
    Comment -> scan_with(source, lexer, scan_comment)
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

fn next_mode(source: String, lexer: Lexer, mode: Mode) -> Mode {
  case mode {
    Base -> next_mode_from_base(lexer, source)
    FreeForm | TagEnd | TripleMustacheEnd | CustomizeDelimiters | Comment ->
      Base
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

fn next_mode_from_base(lexer: Lexer, source: String) -> Mode {
  case can_start_triple_mustache(lexer, source) {
    True -> TripleMustacheStart
    False ->
      case string.starts_with(source, lexer.left_delimiter) {
        False -> FreeForm
        True -> {
          case string.drop_start(source, string.length(lexer.left_delimiter)) {
            "=" <> _ -> CustomizeDelimiters
            "!" <> _ -> Comment
            _ -> TagStart
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

fn scan_free_form(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(text, rest) = splitter.split_before(lexer.tag_start_splitter, source)
  Ok(#(Text(string.length(text), text), rest))
}

fn scan_tag_start(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_open, tail) = splitter.split_after(lexer.tag_start_splitter, source)
  Ok(#(LeftDelimiter(string.length(tag_open)), tail))
}

fn scan_triple_mustache_start(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_open, tail) =
    splitter.split_after(lexer.triple_mustache_start_splitter, source)
  Ok(#(LeftTripleMustache(string.length(tag_open)), tail))
}

fn scan_inside_tag(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  case source {
    "&" <> _ -> scan_single(source, RawVariableIndicator)
    "#" <> _ -> scan_single(source, SectionIndicator)
    "/" <> _ -> scan_single(source, ClosingIndicator)
    "^" <> _ -> scan_single(source, InvertedSectionIndicator)
    ">" <> _ -> scan_single(source, PartialIndicator)
    "$" <> _ -> scan_single(source, BlockIndicator)
    "<" <> _ -> scan_single(source, ParentIndicator)
    "." <> _ -> scan_single(source, Dot)
    _ -> scan_identifier(source, lexer.identifier_splitter)
  }
}

fn scan_single(
  source: String,
  constructor: fn(Int) -> Token,
) -> Result(#(Token, String), LexicalError) {
  Ok(#(constructor(1), string.drop_start(source, 1)))
}

fn scan_identifier(
  source: String,
  identifier_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  use #(value, rest) <- result.map(read_identifier(source, identifier_splitter))
  #(Identifier(string.length(value), value), rest)
}

fn read_identifier(
  source: String,
  identifier_splitter: splitter.Splitter,
) -> Result(#(String, String), LexicalError) {
  let #(value, rest) = splitter.split_before(identifier_splitter, source)
  case string.is_empty(rest) {
    True -> Error(UnterminatedTagError)
    False -> {
      let identifier = string.trim(value)
      case string.is_empty(value) {
        True -> Error(MalformedIdentifierError)
        False -> Ok(#(identifier, rest))
      }
    }
  }
}

fn scan_triple_mustache_end(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_end, tail) =
    splitter.split_after(lexer.triple_mustache_end_splitter, source)
  Ok(#(RightTripleMustache(string.length(tag_end)), tail))
}

fn scan_tag_end(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_end, tail) = splitter.split_after(lexer.tag_end_splitter, source)
  Ok(#(RightDelimiter(string.length(tag_end)), tail))
}

fn scan_customize_delimiters(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let tag_start_length = string.length(lexer.left_delimiter)
  let tag_end_length = string.length(lexer.right_delimiter)
  use #(tag, value, rest) <- result.try(read_tag_and_value(
    source,
    lexer.tag_start_splitter,
    lexer.tag_end_splitter,
    tag_start_length + 1,
    tag_end_length + 1,
  ))
  use #(open, close) <- result.map(read_delimiter_value(value))
  #(SetDelimiters(string.length(tag), open, close), rest)
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

fn scan_comment(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  use #(tag, rest) <- result.map(read_tag(
    source,
    lexer.tag_start_splitter,
    lexer.tag_end_splitter,
  ))
  #(Ignored(string.length(tag)), rest)
}
