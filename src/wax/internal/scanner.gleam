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
  scan_loop(source, "{{", "}}", tag_start_splitter, tag_end_splitter, [])
}

fn scan_loop(
  source: String,
  tag_start: String,
  tag_end: String,
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
        tag_end,
        tag_start_splitter,
        tag_end_splitter,
      ))
      let tail =
        string.slice(
          non_empty,
          token.source_length,
          string.length(non_empty) - token.source_length,
        )
      let #(tag_start, tag_end, tag_start_splitter, tag_end_splitter) = case
        token
      {
        SetDelimiters(_, tag_start, tag_end) -> #(
          tag_start,
          tag_end,
          splitter.new([tag_start]),
          splitter.new([tag_end]),
        )
        _ -> #(tag_start, tag_end, tag_start_splitter, tag_end_splitter)
      }
      scan_loop(
        tail,
        tag_start,
        tag_end,
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
  tag_end: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
) -> Result(Token, LexicalError) {
  let tag_start_length = string.length(tag_start)
  let tag_end_length = string.length(tag_end)
  case string.starts_with(source, tag_start) {
    False -> scan_text(source, tag_start_splitter)
    True ->
      case string.drop_start(source, tag_start_length) {
        "&" <> _ ->
          scan_tag_with_value(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length + 1,
            tag_end_length,
            RawVariable,
          )
        "#" <> _ ->
          scan_tag_with_value(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length + 1,
            tag_end_length,
            SectionStart,
          )
        "/" <> _ ->
          scan_tag_with_value(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length + 1,
            tag_end_length,
            ClosingTag,
          )
        "^" <> _ ->
          scan_tag_with_value(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length + 1,
            tag_end_length,
            InvertedSectionStart,
          )
        ">" <> _ ->
          scan_tag_with_value(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length + 1,
            tag_end_length,
            Partial,
          )
        "$" <> _ ->
          scan_tag_with_value(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length + 1,
            tag_end_length,
            BlockStart,
          )
        "!" <> _ ->
          scan_empty_tag(source, tag_start_splitter, tag_end_splitter, Comment)
        "=" <> _ ->
          scan_set_delimiters(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length + 1,
            tag_end_length + 1,
          )
        _ ->
          scan_tag_with_value(
            source,
            tag_start_splitter,
            tag_end_splitter,
            tag_start_length,
            tag_end_length,
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
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  tag_start_length: Int,
  tag_end_length: Int,
  constructor: fn(Int, String) -> Token,
) -> Result(Token, LexicalError) {
  use #(tag, value) <- result.map(read_tag_and_value(
    source,
    tag_start_splitter,
    tag_end_splitter,
    tag_start_length,
    tag_end_length,
  ))
  constructor(string.length(tag), value)
}

fn read_tag_and_value(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  tag_start_length: Int,
  tag_end_length: Int,
) -> Result(#(String, String), LexicalError) {
  use tag <- result.map(read_tag(source, tag_start_splitter, tag_end_splitter))
  let value = read_value(tag, tag_start_length, tag_end_length)
  #(tag, value)
}

fn read_tag(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
) -> Result(String, LexicalError) {
  let #(tag_start, rest) = splitter.split_after(tag_start_splitter, source)
  let #(tag_middle, tag_end, rest) = splitter.split(tag_end_splitter, rest)
  case string.is_empty(tag_end) && string.is_empty(rest) {
    True -> Error(NoMatchingTagCloseFoundError)
    False -> Ok(tag_start <> tag_middle <> tag_end)
  }
}

fn read_value(
  value: String,
  opening_length: Int,
  closing_length: Int,
) -> String {
  string.slice(
    value,
    opening_length,
    string.length(value) - { opening_length + closing_length },
  )
  |> string.trim()
}

fn scan_empty_tag(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  constructor: fn(Int) -> Token,
) -> Result(Token, LexicalError) {
  use tag <- result.map(read_tag(source, tag_start_splitter, tag_end_splitter))
  constructor(string.length(tag))
}

fn scan_set_delimiters(
  source: String,
  tag_start_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  tag_start_length: Int,
  tag_end_length: Int,
) -> Result(Token, LexicalError) {
  use #(tag, value) <- result.try(read_tag_and_value(
    source,
    tag_start_splitter,
    tag_end_splitter,
    tag_start_length,
    tag_end_length,
  ))
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
