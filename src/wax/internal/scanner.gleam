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

pub fn scan(source: String) -> List(Token) {
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
) -> List(Token) {
  case source {
    "" -> list.reverse(tokens)
    non_empty -> {
      let token =
        scan_token(non_empty, tag_start, tag_start_splitter, tag_end_splitter)
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
) -> Token {
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

fn scan_text(source: String, tag_start_splitter: splitter.Splitter) -> Token {
  let #(text, _) = splitter.split_before(tag_start_splitter, source)
  Text(string.length(text), text)
}

fn scan_tag_with_value(
  source: String,
  tag_end_splitter: splitter.Splitter,
  tag_start_length: Int,
  constructor: fn(Int, String) -> Token,
) -> Token {
  let #(tag, _) = splitter.split_after(tag_end_splitter, source)
  let value =
    tag
    |> strip_delimiters(tag_start_length)
    |> string.trim()
  constructor(string.length(tag), value)
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
) -> Token {
  let #(comment, _) = splitter.split_after(tag_end_splitter, source)
  constructor(string.length(comment))
}

fn scan_set_delimiters(
  source: String,
  tag_end_splitter: splitter.Splitter,
) -> Token {
  let #(tag, _) = splitter.split_after(tag_end_splitter, source)
  let delimiters = string.slice(tag, 3, string.length(tag) - 6)
  let assert [open, close] =
    regexp.from_string("\\s")
    |> result.try(fn(re) { Ok(regexp.split(re, delimiters)) })
    |> result.unwrap([])
  SetDelimiters(string.length(tag), open, close)
}
