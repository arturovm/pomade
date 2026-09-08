import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
import gleam/string

import splitter

type Lexer {
  Lexer(
    tag_start: String,
    tag_end: String,
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
  RawVariable(source_length: Int)
  SectionStart(source_length: Int)
  ClosingTag(source_length: Int)
  InvertedSectionStart(source_length: Int)
  Partial(source_length: Int)
  BlockStart(source_length: Int)
  ParentStart(source_length: Int)
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
  MalformedIdentifier
  NoMatchingTagCloseFoundError
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

fn new_lexer(tag_start: String, tag_end: String) -> Lexer {
  Lexer(
    tag_start:,
    tag_end:,
    tag_start_splitter: splitter.new([tag_start]),
    triple_mustache_start_splitter: splitter.new([left_triple_mustache]),
    identifier_splitter: splitter.new([".", tag_end]),
    triple_mustache_end_splitter: splitter.new([right_triple_mustache]),
    tag_end_splitter: splitter.new([tag_end]),
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
    FreeForm -> {
      use #(token, tail) <- result.map(scan_free_form(
        source,
        lexer.tag_start_splitter,
      ))
      #(lexer, Some(token), tail)
    }
    TagStart -> {
      use #(token, tail) <- result.map(scan_tag_start(
        source,
        lexer.tag_start_splitter,
      ))
      #(lexer, Some(token), tail)
    }
    TripleMustacheStart -> {
      use #(token, tail) <- result.map(scan_triple_mustache_start(
        source,
        lexer.triple_mustache_start_splitter,
      ))
      #(lexer, Some(token), tail)
    }
    InsideTag -> {
      use #(token, tail) <- result.map(scan_inside_tag(
        source,
        lexer.identifier_splitter,
      ))
      #(lexer, Some(token), tail)
    }
    TripleMustacheEnd -> {
      use #(token, tail) <- result.map(scan_triple_mustache_end(
        source,
        lexer.triple_mustache_end_splitter,
      ))
      #(lexer, Some(token), tail)
    }
    TagEnd -> {
      use #(token, tail) <- result.map(scan_tag_end(
        source,
        lexer.tag_end_splitter,
      ))
      #(lexer, Some(token), tail)
    }
    CustomizeDelimiters -> {
      use #(token, tail) <- result.map(scan_customize_delimiters(
        source,
        lexer.tag_start,
        lexer.tag_end,
        lexer.tag_start_splitter,
        lexer.tag_end_splitter,
      ))
      let assert SetDelimiters(_, tag_start, tag_end) = token
      let lexer = new_lexer(tag_start, tag_end)
      #(lexer, Some(token), tail)
    }
    Comment -> {
      use #(token, tail) <- result.map(scan_comment(
        source,
        lexer.tag_start_splitter,
        lexer.tag_end_splitter,
      ))
      #(lexer, Some(token), tail)
    }
  }
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
          case string.starts_with(source, lexer.tag_end) {
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
      case string.starts_with(source, lexer.tag_start) {
        False -> FreeForm
        True -> {
          case string.drop_start(source, string.length(lexer.tag_start)) {
            "=" <> _ -> CustomizeDelimiters
            "!" <> _ -> Comment
            _ -> TagStart
          }
        }
      }
  }
}

fn can_start_triple_mustache(lexer: Lexer, source: String) -> Bool {
  lexer.tag_start == default_left_delimiter
  && string.starts_with(source, left_triple_mustache)
}

fn can_end_triple_mustache(lexer: Lexer, source: String) -> Bool {
  lexer.tag_end == default_right_delimiter
  && string.starts_with(source, right_triple_mustache)
}

fn scan_free_form(
  source: String,
  tag_start_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  let #(text, rest) = splitter.split_before(tag_start_splitter, source)
  Ok(#(Text(string.length(text), text), rest))
}

fn scan_tag_start(
  source: String,
  tag_start_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_open, tail) = splitter.split_after(tag_start_splitter, source)
  Ok(#(LeftDelimiter(string.length(tag_open)), tail))
}

fn scan_triple_mustache_start(
  source: String,
  triple_mustache_start_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_open, tail) =
    splitter.split_after(triple_mustache_start_splitter, source)
  Ok(#(LeftTripleMustache(string.length(tag_open)), tail))
}

fn scan_inside_tag(
  source: String,
  identifier_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  case source {
    "&" <> _ -> scan_single(source, RawVariable)
    "#" <> _ -> scan_single(source, SectionStart)
    "/" <> _ -> scan_single(source, ClosingTag)
    "^" <> _ -> scan_single(source, InvertedSectionStart)
    ">" <> _ -> scan_single(source, Partial)
    "$" <> _ -> scan_single(source, BlockStart)
    "<" <> _ -> scan_single(source, ParentStart)
    "." <> _ -> scan_single(source, Dot)
    _ -> scan_identifier(source, identifier_splitter)
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
  let identifier = string.trim(value)
  case string.is_empty(value) || string.is_empty(rest) {
    True -> Error(MalformedIdentifier)
    False -> Ok(#(identifier, rest))
  }
}

fn scan_triple_mustache_end(
  source: String,
  triple_mustache_end_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_end, tail) =
    splitter.split_after(triple_mustache_end_splitter, source)
  Ok(#(RightTripleMustache(string.length(tag_end)), tail))
}

fn scan_tag_end(
  source: String,
  tag_end_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  let #(tag_end, tail) = splitter.split_after(tag_end_splitter, source)
  Ok(#(RightDelimiter(string.length(tag_end)), tail))
}

fn scan_customize_delimiters(
  source: String,
  tag_start: String,
  tag_end: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  let tag_start_length = string.length(tag_start)
  let tag_end_length = string.length(tag_end)
  use #(token, tail) <- result.map(scan_set_delimiters(
    source,
    tag_start_splitter,
    tag_end_splitter,
    tag_start_length + 1,
    tag_end_length + 1,
  ))
  #(token, tail)
}

fn scan_set_delimiters(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  tag_start_length: Int,
  tag_end_length: Int,
) -> Result(#(Token, String), LexicalError) {
  use #(tag, value, rest) <- result.try(read_tag_and_value(
    source,
    tag_start_splitter,
    tag_end_splitter,
    tag_start_length,
    tag_end_length,
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
    True -> Error(NoMatchingTagCloseFoundError)
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
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  use #(token, tail) <- result.map(scan_ignored(
    source,
    tag_start_splitter,
    tag_end_splitter,
  ))
  #(token, tail)
}

fn scan_ignored(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  use #(tag, rest) <- result.map(read_tag(
    source,
    tag_start_splitter,
    tag_end_splitter,
  ))
  #(Ignored(string.length(tag)), rest)
}
