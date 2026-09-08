import gleam/list
import gleam/regexp
import gleam/result
import gleam/string

import splitter

type Mode {
  Base
  FreeForm
  TagStart
  InsideTag
  TagEnd
  CustomizeDelimiters
  Comment
}

pub type Token {
  // general text
  Text(source_length: Int, value: String)
  // tags
  LeftDelimiter(source_length: Int)
  RawVariable(source_length: Int)
  SectionStart(source_length: Int)
  ClosingTag(source_length: Int)
  InvertedSectionStart(source_length: Int)
  Partial(source_length: Int)
  BlockStart(source_length: Int)
  ParentStart(source_length: Int)
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

pub fn scan(source: String) -> Result(List(Token), LexicalError) {
  let tag_start_splitter = splitter.new([default_left_delimiter])
  let identifier_splitter = splitter.new([".", default_right_delimiter])
  let tag_end_splitter = splitter.new([default_right_delimiter])
  scan_loop(
    source,
    Base,
    default_left_delimiter,
    default_right_delimiter,
    tag_start_splitter,
    identifier_splitter,
    tag_end_splitter,
    [],
  )
}

fn scan_loop(
  source: String,
  mode: Mode,
  tag_start: String,
  tag_end: String,
  tag_start_splitter: splitter.Splitter,
  identifier_splitter: splitter.Splitter,
  tag_end_splitter: splitter.Splitter,
  tokens: List(Token),
) -> Result(List(Token), LexicalError) {
  case source {
    "" -> Ok(list.reverse(tokens))
    non_empty -> {
      case mode {
        Base ->
          scan_loop(
            source,
            next_mode(source, tag_start, tag_end, mode),
            tag_start,
            tag_end,
            tag_start_splitter,
            identifier_splitter,
            tag_end_splitter,
            tokens,
          )
        FreeForm -> {
          use #(token, tail) <- result.try(scan_free_form(
            non_empty,
            tag_start_splitter,
          ))
          scan_loop(
            tail,
            next_mode(tail, tag_start, tag_end, mode),
            tag_start,
            tag_end,
            tag_start_splitter,
            identifier_splitter,
            tag_end_splitter,
            list.prepend(tokens, token),
          )
        }
        TagStart -> {
          use #(token, tail) <- result.try(scan_tag_start(
            non_empty,
            tag_start_splitter,
          ))
          scan_loop(
            tail,
            next_mode(tail, tag_start, tag_end, mode),
            tag_start,
            tag_end,
            tag_start_splitter,
            identifier_splitter,
            tag_end_splitter,
            list.prepend(tokens, token),
          )
        }
        InsideTag -> {
          use #(token, tail) <- result.try(scan_inside_tag(
            source,
            identifier_splitter,
          ))
          scan_loop(
            tail,
            next_mode(tail, tag_start, tag_end, mode),
            tag_start,
            tag_end,
            tag_start_splitter,
            identifier_splitter,
            tag_end_splitter,
            list.prepend(tokens, token),
          )
        }
        TagEnd -> {
          use #(token, tail) <- result.try(scan_tag_end(
            source,
            tag_end_splitter,
          ))
          scan_loop(
            tail,
            next_mode(tail, tag_start, tag_end, mode),
            tag_start,
            tag_end,
            tag_start_splitter,
            identifier_splitter,
            tag_end_splitter,
            list.prepend(tokens, token),
          )
        }
        CustomizeDelimiters -> {
          use #(token, tail) <- result.try(scan_customize_delimiters(
            source,
            tag_start,
            tag_end,
            tag_start_splitter,
            tag_end_splitter,
          ))
          let assert SetDelimiters(_, tag_start, tag_end) = token
          let tag_start_splitter = splitter.new([tag_start])
          let identifier_splitter = splitter.new([".", tag_end])
          let tag_end_splitter = splitter.new([tag_end])
          scan_loop(
            tail,
            next_mode(tail, tag_start, tag_end, mode),
            tag_start,
            tag_end,
            tag_start_splitter,
            identifier_splitter,
            tag_end_splitter,
            list.prepend(tokens, token),
          )
        }
        Comment -> {
          use #(token, tail) <- result.try(scan_comment(
            source,
            tag_start_splitter,
            tag_end_splitter,
          ))
          scan_loop(
            tail,
            next_mode(tail, tag_start, tag_end, mode),
            tag_start,
            tag_end,
            tag_start_splitter,
            identifier_splitter,
            tag_end_splitter,
            list.prepend(tokens, token),
          )
        }
      }
    }
  }
}

fn next_mode(
  source: String,
  tag_start: String,
  tag_end: String,
  mode: Mode,
) -> Mode {
  case mode {
    Base | FreeForm | TagEnd | CustomizeDelimiters | Comment ->
      next_mode_from_base(source, tag_start)
    TagStart -> InsideTag
    InsideTag ->
      case string.starts_with(source, tag_end) {
        False -> InsideTag
        True -> TagEnd
      }
  }
}

fn next_mode_from_base(source, tag_start) {
  case string.starts_with(source, tag_start) {
    False -> FreeForm
    True -> {
      case string.drop_start(source, string.length(tag_start)) {
        "=" <> _ -> CustomizeDelimiters
        "!" <> _ -> Comment
        _ -> TagStart
      }
    }
  }
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
  case string.is_empty(rest) {
    True -> Error(MalformedIdentifier)
    False -> Ok(#(identifier, rest))
  }
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
