import gleam/list
import gleam/regexp
import gleam/result
import gleam/string

import splitter

pub type Token {
  Text(source_length: Int, value: String)
  Variable(source_length: Int, value: String)
  RawVariable(source_length: Int, value: String)
  SectionStart(source_length: Int, value: String)
  ClosingTag(source_length: Int, value: String)
  InvertedSectionStart(source_length: Int, value: String)
  Partial(source_length: Int, value: String)
  BlockStart(source_length: Int, value: String)
  SetDelimiters(source_length: Int, tag_start: String, tag_end: String)
  Comment(source_length: Int)
}

pub type LexicalError {
  NoMatchingTagCloseFoundError
  MalformedSetDelimitersError
}

pub fn scan(source: String) -> Result(List(Token), LexicalError) {
  let tag_start_splitter = splitter.new(["{{"])
  let tag_end_splitter = splitter.new(["}}"])
  scan_loop(source, "{{", tag_start_splitter, tag_end_splitter, [])
}

fn scan_loop(
  source: String,
  tag_start: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  tokens: List(Token),
) -> Result(List(Token), LexicalError) {
  case source {
    "" -> Ok(list.reverse(tokens))
    non_empty -> {
      use token <- result.try(scan_token(
        non_empty,
        tag_start,
        tag_start_splitter,
        tag_end_splitter,
      ))
      let tail =
        string.slice(
          non_empty,
          token.source_length,
          string.length(non_empty) - token.source_length,
        )
      let #(tag_start, tag_start_splitter, tag_end_splitter) = case token {
        SetDelimiters(_, tag_start, tag_end) -> #(
          tag_start,
          splitter.new([tag_start]),
          splitter.new([tag_end]),
        )
        _ -> #(tag_start, tag_start_splitter, tag_end_splitter)
      }
      scan_loop(
        tail,
        tag_start,
        tag_start_splitter,
        tag_end_splitter,
        list.prepend(tokens, token),
      )
    }
  }
}

fn scan_token(
  source: String,
  tag_start: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
) -> Result(Token, LexicalError) {
  let tag_start_length = string.length(tag_start)
  case string.starts_with(source, tag_start) {
    False -> scan_text(source, tag_start_splitter)
    True ->
      case string.drop_start(source, tag_start_length) {
        "&" <> _ ->
          scan_tag_with_value(
            source,
            tag_end_splitter,
            tag_start_length + 1,
            RawVariable,
          )
        "#" <> _ ->
          scan_tag_with_value(
            source,
            tag_end_splitter,
            tag_start_length + 1,
            SectionStart,
          )
        "/" <> _ ->
          scan_tag_with_value(
            source,
            tag_end_splitter,
            tag_start_length + 1,
            ClosingTag,
          )
        "^" <> _ ->
          scan_tag_with_value(
            source,
            tag_end_splitter,
            tag_start_length + 1,
            InvertedSectionStart,
          )
        ">" <> _ ->
          scan_tag_with_value(
            source,
            tag_end_splitter,
            tag_start_length + 1,
            Partial,
          )
        "$" <> _ ->
          scan_tag_with_value(
            source,
            tag_end_splitter,
            tag_start_length + 1,
            BlockStart,
          )
        "!" <> _ -> scan_empty_tag(source, tag_end_splitter, Comment)
        "=" <> _ -> scan_set_delimiters(source, tag_end_splitter)
        _ ->
          scan_tag_with_value(
            source,
            tag_end_splitter,
            tag_start_length,
            Variable,
          )
      }
  }
}

fn scan_text(
  source: String,
  tag_start_splitter: splitter.Splitter,
) -> Result(Token, LexicalError) {
  let #(text, _) = splitter.split_before(tag_start_splitter, source)
  Ok(Text(string.length(text), text))
}

fn scan_tag_with_value(
  source: String,
  tag_end_splitter: splitter.Splitter,
  tag_start_length: Int,
  constructor: fn(Int, String) -> Token,
) -> Result(Token, LexicalError) {
  use tag <- result.map(scan_tag(source, tag_end_splitter))
  let value =
    tag
    |> strip_delimiters(tag_start_length)
    |> string.trim()
  constructor(string.length(tag), value)
}

fn scan_tag(
  source: String,
  tag_end_splitter: splitter.Splitter,
) -> Result(String, LexicalError) {
  let #(partial_tag, tag_end, rest) = splitter.split(tag_end_splitter, source)
  case string.is_empty(tag_end) && string.is_empty(rest) {
    True -> Error(NoMatchingTagCloseFoundError)
    False -> Ok(partial_tag <> tag_end)
  }
}

fn strip_delimiters(value: String, opening_length: Int) -> String {
  string.slice(
    value,
    opening_length,
    string.length(value) - { opening_length + 2 },
  )
}

fn scan_empty_tag(
  source: String,
  tag_end_splitter: splitter.Splitter,
  constructor: fn(Int) -> Token,
) -> Result(Token, LexicalError) {
  use tag <- result.map(scan_tag(source, tag_end_splitter))
  constructor(string.length(tag))
}

fn scan_set_delimiters(
  source: String,
  tag_end_splitter: splitter.Splitter,
) -> Result(Token, LexicalError) {
  use tag <- result.try(scan_tag(source, tag_end_splitter))
  let value =
    string.slice(tag, 3, string.length(tag) - 6)
    |> string.trim()
  use #(open, close) <- result.map(scan_delimiter_value(value))
  SetDelimiters(string.length(tag), open, close)
}

fn scan_delimiter_value(
  value: String,
) -> Result(#(String, String), LexicalError) {
  let assert Ok(re) = regexp.from_string("\\s+")
  case regexp.split(re, value) {
    [open, close] -> Ok(#(open, close))
    _ -> Error(MalformedSetDelimitersError)
  }
}
