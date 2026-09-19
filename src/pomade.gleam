import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
import gleam/string
import gleam/string_tree.{type StringTree}

import splitter

/// `Template` represents a compiled template. Since this is a type alias to a
/// function, simply pass it a dictionary of input values.
pub type Template =
  fn(Dict(String, Value)) -> Result(String, Error)

/// `Error` aggregates all the possible error types that can be emitted by the
/// different rendering phases.
pub type Error {
  /// `ScannerError` reports a lexical error, encountered during scanning.
  ScannerError(LexicalError)
  /// `ParserError` reports a syntax error, encountered during parsing.
  ParserError(SyntaxError)
  /// `InterpreterError` reports a runtime error, encountered during interpreting.
  InterpreterError(RuntimeError)
}

/// `render` renders a template source string directly. Useful when convenience
/// is the priority.
pub fn render(template: String, environment: Dict(String, Value)) -> String {
  case scan(template) {
    Error(_) -> ""
    Ok(tokens) ->
      case parse(tokens) {
        Error(_) -> ""
        Ok(ast) ->
          case interpret(ast, environment) {
            Error(_) -> ""
            Ok(result) -> result
          }
      }
  }
}

/// `compile` prepares a template for future application, to avoid the overhead
/// of scanning and parsing a template from scratch every time. Prefer this
/// when speed is important.
pub fn compile(template: String) -> Result(Template, Error) {
  use tokens <- result.try(scan(template) |> result.map_error(ScannerError))
  use ast <- result.map(parse(tokens) |> result.map_error(ParserError))
  fn(env: Dict(String, Value)) -> Result(String, Error) {
    interpret(ast, env) |> result.map_error(InterpreterError)
  }
}

// scanner

type Lexer {
  Lexer(
    left_delimiter: String,
    right_delimiter: String,
    free_form_splitter: splitter.Splitter,
    triple_mustache_start_splitter: splitter.Splitter,
    identifier_splitter: splitter.Splitter,
    triple_mustache_end_splitter: splitter.Splitter,
    tag_end_splitter: splitter.Splitter,
  )
}

type Mode {
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

@internal
pub type Token {
  // general text
  TextLiteral(lexeme: String)
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
  UnexpectedCharacterError
}

const default_left_delimiter: String = "{{"

const default_right_delimiter: String = "}}"

const left_triple_mustache: String = "{{{"

const right_triple_mustache: String = "}}}"

@internal
pub fn scan(source: String) -> Result(List(Token), LexicalError) {
  let lexer = new_lexer(default_left_delimiter, default_right_delimiter)
  scan_loop(lexer, source, Base, [])
}

fn new_lexer(left_delimiter: String, right_delimiter: String) -> Lexer {
  Lexer(
    left_delimiter: left_delimiter,
    right_delimiter: right_delimiter,
    free_form_splitter: splitter.new(["\r\n", "\n", left_delimiter]),
    triple_mustache_start_splitter: splitter.new([left_triple_mustache]),
    identifier_splitter: splitter.new([".", right_delimiter]),
    triple_mustache_end_splitter: splitter.new([right_triple_mustache]),
    tag_end_splitter: splitter.new([right_delimiter]),
  )
}

fn scan_loop(
  lexer: Lexer,
  source: String,
  mode: Mode,
  tokens: List(Token),
) -> Result(List(Token), LexicalError) {
  case source {
    "" -> {
      let tokens = list.prepend(tokens, Eof)
      Ok(list.reverse(tokens))
    }
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
    LineEnd -> scan_with(source, lexer, scan_line_end)
    TagStart -> scan_with(source, lexer, scan_tag_start)
    TripleMustacheStart -> scan_with(source, lexer, scan_triple_mustache_start)
    InsideTag -> scan_with(source, lexer, scan_inside_tag)
    TripleMustacheEnd -> scan_with(source, lexer, scan_triple_mustache_end)
    TagEnd -> scan_with(source, lexer, scan_tag_end)
    CustomizeDelimiters -> {
      use #(token, tail) <- result.map(scan_customize_delimiters(source, lexer))
      let assert SetDelimiters(left_delimiter, right_delimiter) = token
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

fn next_mode_from_base(lexer: Lexer, source: String) -> Mode {
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

fn scan_free_form(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(text, rest) = splitter.split_before(lexer.free_form_splitter, source)
  Ok(#(TextLiteral(text), rest))
}

fn scan_line_end(
  source: String,
  _lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  case source {
    "\r\n" as value <> rest | "\n" as value <> rest -> {
      Ok(#(NewlineLiteral(value), rest))
    }
    _ -> Error(UnexpectedCharacterError)
  }
}

fn scan_tag_start(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(_, tail) = splitter.split_after(lexer.free_form_splitter, source)
  Ok(#(LeftDelimiter, tail))
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
  token: Token,
) -> Result(#(Token, String), LexicalError) {
  Ok(#(token, string.drop_start(source, 1)))
}

fn scan_identifier(
  source: String,
  identifier_splitter: splitter.Splitter,
) -> Result(#(Token, String), LexicalError) {
  use #(value, rest) <- result.map(read_identifier(source, identifier_splitter))
  #(Identifier(value), rest)
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
  let #(_, tail) =
    splitter.split_after(lexer.triple_mustache_end_splitter, source)
  Ok(#(RightTripleMustache, tail))
}

fn scan_tag_end(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  let #(_, tail) = splitter.split_after(lexer.tag_end_splitter, source)
  Ok(#(RightDelimiter, tail))
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

fn scan_comment(
  source: String,
  lexer: Lexer,
) -> Result(#(Token, String), LexicalError) {
  use #(_, rest) <- result.map(read_tag(
    source,
    lexer.free_form_splitter,
    lexer.tag_end_splitter,
  ))
  #(Ignored, rest)
}

// parser

// Mustache syntactical grammar:
//
// template                 -> expression* EOF ;
// expression               -> parent
// parent                   -> parent_opening expression* closing_tag | block;
// parent_opening           -> LEFT_DELIMITER "<" name RIGHT_DELIMITER ;
// block                    -> block_opening expression* closing_tag | inverted_section ;
// block_opening            -> LEFT_DELIMITER "$" name RIGHT_DELIMITER ;
// inverted_section         -> inverted_section_opening expression* closing_tag | section;
// inverted_section_opening -> LEFT_DELIMITER "^" name RIGHT_DELIMITER ;
// section                  -> section_opening expression* closing_tag | partial ;
// section_opening          -> LEFT_DELIMITER "#" name RIGHT_DELIMITER ;
// closing_tag              -> LEFT_DELIMITER "/" name RIGHT_DELIMITER ;
// partial                  -> LEFT_DELIMITER ">" name RIGHT_DELIMITER | raw_variable ;
// raw_variable             -> ("{{{" name "}}}") | (LEFT_DELIMITER "&" name RIGHT_DELIMITER) | variable ;
// variable                 -> LEFT_DELIMITER name RIGHT_DELIMITER | primary ;
// name                     -> "." | (IDENTIFIER? ("." IDENTIFIER)*)) ;
// primary                  -> TEXT | NEWLINE

@internal
pub type Expression {
  Text(value: String)
  Newline(value: String)
  Variable(path: List(String))
  RawVariable(path: List(String))
  Section(path: List(String), content: List(Expression))
  InvertedSection(path: List(String), content: List(Expression))
  Partial(path: List(String))
  Block(path: List(String), content: List(Expression))
  Parent(path: List(String), content: List(Expression))
}

/// `SyntaxError` represents an error encountered during parsing.
pub type SyntaxError {
  /// `UnexpectedTokenError` is returned when a token different from what the
  /// grammar indicates is found.
  UnexpectedTokenError(Token)
  /// `UnexpectedEndOfInputError` is used to report that more tokens were
  /// expected, but the parser unexpectedly consumed the whole input.
  UnexpectedEndOfInputError
  /// `NoMatchingClosingTagError` is returned when a `{{/closing_tag}}` was
  /// expected, but none was found.
  NoMatchingClosingTagError
}

@internal
pub fn parse(tokens: List(Token)) -> Result(List(Expression), SyntaxError) {
  parse_template(tokens)
}

// rules

fn parse_template(
  tokens: List(Token),
) -> Result(List(Expression), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, []))
  use _ <- result.map(expect_token(tail, Eof))
  expressions
}

fn parse_expressions(
  tokens: List(Token),
  acc: List(Expression),
) -> Result(#(List(Expression), List(Token)), SyntaxError) {
  case tokens {
    [Eof] -> Ok(#(list.reverse(acc), tokens))
    [LeftDelimiter, ClosingIndicator, ..] -> Ok(#(list.reverse(acc), tokens))
    non_empty -> {
      use #(expression, tail) <- result.try(parse_expression(non_empty))
      parse_expressions(tail, list.prepend(acc, expression))
    }
  }
}

fn parse_expression(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  parse_parent(tokens)
}

fn parse_parent(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [LeftDelimiter, ParentIndicator, ..] ->
      parse_enclosed(tokens, parse_parent_opening, Parent)
    _ -> parse_block(tokens)
  }
}

fn parse_parent_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, ParentIndicator)
}

fn parse_block(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [LeftDelimiter, BlockIndicator, ..] ->
      parse_enclosed(tokens, parse_block_opening, Block)
    _ -> parse_inverted_section(tokens)
  }
}

fn parse_block_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, BlockIndicator)
}

fn parse_inverted_section(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [LeftDelimiter, InvertedSectionIndicator, ..] ->
      parse_enclosed(tokens, parse_inverted_section_opening, InvertedSection)
    _ -> parse_section(tokens)
  }
}

fn parse_inverted_section_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, InvertedSectionIndicator)
}

fn parse_section(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [LeftDelimiter, SectionIndicator, ..] ->
      parse_enclosed(tokens, parse_section_opening, Section)
    _ -> parse_partial(tokens)
  }
}

fn parse_section_opening(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  parse_tag_with_indicator(tokens, SectionIndicator)
}

fn parse_closing_tag(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    ClosingIndicator,
  ))
  #(path, tail)
}

fn parse_partial(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [LeftDelimiter, PartialIndicator, ..] -> {
      use #(path, tail) <- result.map(parse_tag_with_indicator(
        tokens,
        PartialIndicator,
      ))
      #(Partial(path), tail)
    }
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [LeftTripleMustache, ..] -> {
      parse_raw_variable_with_triple_mustache(tokens)
    }
    [LeftDelimiter, RawVariableIndicator, ..] ->
      parse_raw_variable_with_delimiters(tokens)
    _ -> parse_variable(tokens)
  }
}

fn parse_raw_variable_with_triple_mustache(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect_token(tokens, LeftTripleMustache))
  let #(path, tail) = parse_name(tail)
  use #(_, tail) <- result.map(expect_token(tail, RightTripleMustache))
  #(RawVariable(path), tail)
}

fn parse_raw_variable_with_delimiters(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(path, tail) <- result.map(parse_tag_with_indicator(
    tokens,
    RawVariableIndicator,
  ))
  #(RawVariable(path), tail)
}

fn parse_variable(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [LeftDelimiter, ..] -> {
      use #(_, tail) <- result.try(expect_token(tokens, LeftDelimiter))
      let #(path, tail) = parse_name(tail)
      use #(_, tail) <- result.map(expect_token(tail, RightDelimiter))
      #(Variable(path), tail)
    }
    _ -> parse_primary(tokens)
  }
}

fn parse_name(tokens: List(Token)) -> #(List(String), List(Token)) {
  case tokens {
    [Dot, ..tail] -> #(["."], tail)
    [Identifier(value), ..tail] -> {
      name_loop(tail, [value])
    }
    _ -> #([], tokens)
  }
}

fn name_loop(
  tokens: List(Token),
  path: List(String),
) -> #(List(String), List(Token)) {
  case tokens {
    [Dot, Identifier(value), ..tail] ->
      name_loop(tail, list.prepend(path, value))
    any -> {
      #(list.reverse(path), any)
    }
  }
}

fn parse_primary(
  tokens: List(Token),
) -> Result(#(Expression, List(Token)), SyntaxError) {
  case tokens {
    [TextLiteral(value), Ignored, NewlineLiteral(_), ..tail] -> {
      case is_blank(value) {
        True -> parse_primary(tail)
        False -> Ok(#(Text(value), list.drop(tokens, 1)))
      }
    }
    [Ignored, ..tail] -> parse_primary(tail)
    [TextLiteral(value), ..tail] -> Ok(#(Text(value), tail))
    [NewlineLiteral(value), ..tail] -> Ok(#(Newline(value), tail))
    [any, ..] -> Error(UnexpectedTokenError(any))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// helpers

fn parse_tag_with_indicator(
  tokens: List(Token),
  indicator: Token,
) -> Result(#(List(String), List(Token)), SyntaxError) {
  use #(_, tail) <- result.try(expect_token(tokens, LeftDelimiter))
  use #(_, tail) <- result.try(expect_token(tail, indicator))
  let #(path, tail) = parse_name(tail)
  use #(_, tail) <- result.map(expect_token(tail, RightDelimiter))
  #(path, tail)
}

fn parse_enclosed(
  tokens: List(Token),
  opening_rule: fn(List(Token)) ->
    Result(#(List(String), List(Token)), SyntaxError),
  expr_constructor: fn(List(String), List(Expression)) -> Expression,
) -> Result(#(Expression, List(Token)), SyntaxError) {
  use #(path, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, []))
  use #(closing_path, tail) <- result.try(parse_closing_tag(tail))
  case path == closing_path {
    False -> Error(NoMatchingClosingTagError)
    True -> Ok(#(expr_constructor(path, expressions), tail))
  }
}

fn is_blank(string: String) -> Bool {
  case string {
    "" -> True
    " " <> tail | "\t" <> tail -> is_blank(tail)
    _ -> False
  }
}

fn expect_token(
  tokens: List(Token),
  expected: Token,
) -> Result(#(Token, List(Token)), SyntaxError) {
  case tokens {
    [head, ..tail] ->
      case head == expected {
        True -> Ok(#(head, tail))
        False -> Error(UnexpectedTokenError(head))
      }
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// interpreter

/// `RuntimeError` represents an error encountered during interpreting.
pub type RuntimeError {
  /// `UnknownExpressionError` is returned when the interpreter doesn't know
  /// how to evaluate a given expression.
  UnknownExpressionError
}

@internal
pub fn interpret(
  template: List(Expression),
  environment: Dict(String, Value),
) -> Result(String, RuntimeError) {
  use trees <- result.map(evaluate_exprs(template, environment, []))
  trees
  |> list.fold(string_tree.new(), string_tree.append_tree)
  |> string_tree.to_string()
}

fn evaluate_exprs(
  exprs: List(Expression),
  env: Dict(String, Value),
  acc: List(StringTree),
) -> Result(List(StringTree), RuntimeError) {
  case exprs {
    [] -> Ok(list.reverse(acc))
    [expr, ..tail] -> {
      use value <- result.try(evaluate(expr, env))
      evaluate_exprs(tail, env, list.prepend(acc, value))
    }
  }
}

fn evaluate(
  expr: Expression,
  env: Dict(String, Value),
) -> Result(StringTree, RuntimeError) {
  case expr {
    Text(value) | Newline(value) -> Ok(string_tree.from_string(value))
    Variable(_) -> evaluate_variable(expr, env)
    _ -> Error(UnknownExpressionError)
  }
}

fn evaluate_variable(
  expr: Expression,
  env: Dict(String, Value),
) -> Result(StringTree, RuntimeError) {
  let assert Variable(path) = expr
  Dict(env)
  |> get(path)
  |> string_tree.from_string()
  |> Ok()
}

// environment

/// `Value` represents any of the possible types that can be passed as the
/// right-hand side of the dictionary used as input for Mustache templates
/// (what Mustache calls a "hash" in its official documentation).
pub type Value {
  Dict(Dict(String, Value))
  Int(Int)
  String(String)
}

fn get(env: Value, path: List(String)) -> String {
  case get_path(env, path) {
    Ok(val) -> format(val)
    Error(Nil) -> ""
  }
}

fn get_path(env: Value, path: List(String)) -> Result(Value, Nil) {
  case path {
    [] -> Error(Nil)
    [key] -> get_in_val(env, key)
    [key, ..tail] -> {
      use val <- result.try(get_in_val(env, key))
      get_path(val, tail)
    }
  }
}

fn get_in_val(env: Value, key: String) -> Result(Value, Nil) {
  case env {
    Dict(dictionary) -> dict.get(dictionary, key)
    _ -> Error(Nil)
  }
}

fn format(val: Value) -> String {
  case val {
    Int(value) -> int.to_string(value)
    String(value) -> value
    _ -> ""
  }
}
