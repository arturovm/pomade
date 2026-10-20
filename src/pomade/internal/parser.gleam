//// Mustache syntactical grammar:
////
//// template        -> {expression} EOF ;
//// expression      -> Indent ;
//// Indent          -> INDENT | Leading ;
//// Leading         -> LEADING | Block ;
//// Block           -> [PADDING] BLOCK_START {expression} END | Parent ;
//// Parent          -> [PADDING] PARENT_START {expression} END | InvertedSection ;
//// InvertedSection -> INVERTED_SECTION_START {expression} END | Section;
//// Section         -> SECTION_START {expression} END | Partial ;
//// Partial         -> [PADDING] PARTIAL | RawVariable ;
//// RawVariable     -> (TRIPLE_MUSTACHE | RAW_VARIABLE) | Variable ;
//// Variable        -> VARIABLE | Literal ;
//// Literal         -> TEXT | WHITESPACE | NEWLINE ;

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import pomade/internal/rewriter

pub type Expression {
  // Indent is a marker for applying indentation at runtime
  Indent
  // Leading is a special expression used to manipulate whitespace at the
  // beginning of a line. I added this expression solely to deal with
  // the weird rules of the inheritance spec around indentation and
  // de-indentation
  Leading(String)
  Literal(token: rewriter.Token)
  Variable(token: rewriter.Token)
  RawVariable(token: rewriter.Token)
  Section(token: rewriter.Token, content: List(Expression))
  InvertedSection(token: rewriter.Token, content: List(Expression))
  Partial(name: rewriter.Token, indentation: Option(String))
  Block(token: rewriter.Token, indentation: String, content: List(Expression))
  Parent(
    token: rewriter.Token,
    indentation: Option(String),
    content: List(Expression),
  )
}

/// `SyntaxError` represents an error encountered during parsing.
pub type SyntaxError {
  /// `UnexpectedTokenError` is returned when a token different from what the
  /// grammar indicates is found.
  UnexpectedTokenError(rewriter.Token)
  /// `UnexpectedEndOfInputError` is used to report that more tokens were
  /// expected, but the parser unexpectedly consumed the whole input.
  UnexpectedEndOfInputError
  /// `NoMatchingClosingTagError` is returned when a `{{/closing_tag}}` was
  /// expected, but none was found.
  NoMatchingEndTagError(rewriter.Token)
}

pub fn parse(
  tokens: List(rewriter.Token),
) -> Result(List(Expression), SyntaxError) {
  parse_template(tokens)
}

// rules

fn parse_template(
  tokens: List(rewriter.Token),
) -> Result(List(Expression), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, [], None))
  use _ <- result.map(parse_eof(tail))
  expressions
}

fn parse_expressions(
  tokens: List(rewriter.Token),
  acc: List(Expression),
  dedent: Option(String),
) -> Result(#(List(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_)] | [rewriter.End(_, _), ..] ->
      Ok(#(list.reverse(acc), tokens))
    non_empty ->
      case parse_expression(non_empty, dedent) {
        Ok(#(Some(some), tail)) ->
          parse_expressions(tail, [some, ..acc], dedent)
        Ok(#(None, tail)) -> parse_expressions(tail, acc, dedent)
        Error(error) -> Error(error)
      }
  }
}

fn parse_expression(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  parse_indent(tokens, dedent)
}

fn parse_indent(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Indent(_), ..tail] -> Ok(#(Some(Indent), tail))
    _ -> parse_leading(tokens, dedent)
  }
}

fn parse_leading(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Leading(_, lexeme), ..tail] ->
      // De-indent the line according to the dedent value, in case this
      // expression is inside a block expression
      Ok(#(Some(Leading(remove_prefix(lexeme, dedent))), tail))
    _ -> parse_block(tokens, dedent)
  }
}

fn parse_block(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [
      rewriter.Padding(_, indentation),
      rewriter.BlockStart(_, _) as start,
      ..tail
    ] -> parse_block_content(tail, start, Some(indentation), dedent)
    [rewriter.BlockStart(_, _) as start, ..tail] ->
      parse_block_content(tail, start, None, dedent)
    _ -> parse_parent(tokens, dedent)
  }
}

fn parse_block_content(
  tokens: List(rewriter.Token),
  start: rewriter.Token,
  indentation: Option(String),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  // A block's internal indentation, if any
  let intrinsic_indentation = case tokens {
    [rewriter.Indent(_), rewriter.Leading(_, lexeme), ..] -> Some(lexeme)
    // As a special case, if the first line has no indentation at all, then we
    // consider the block's internal inentation to be the empty string, which
    // always happens in lines with content in the spec
    [rewriter.Indent(_), ..] -> Some("")
    _ -> None
  }
  // The indentation to use when rendering
  let indentation = case intrinsic_indentation, tokens {
    // Intrinsic indentation takes precedence
    Some(lexeme), _ -> lexeme
    // After the intrinsic indentation, the external indentation takes
    // precedence, in case the block is surrounded by another block (third
    // clause).
    None, _ -> option.unwrap(indentation, "")
  }
  use #(expressions, tail) <- result.try(parse_expressions(
    tokens,
    [],
    // parse internal expressions, de-indenting either by this block's internal
    // indentation, or by the dedent value from a possible surrounding block.
    option.or(intrinsic_indentation, dedent),
  ))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True ->
      // The block's runtime indentation is equal to the indentation that took
      // precedence above, minus the dedent which was possibly inherited from
      // another block.
      Ok(#(
        Some(Block(start, remove_prefix(indentation, dedent), expressions)),
        tail,
      ))
  }
}

fn parse_parent(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [
      rewriter.Padding(_, indentation),
      rewriter.ParentStart(_, _) as start,
      ..tail
    ] -> parse_parent_content(tail, start, Some(indentation), dedent)
    [rewriter.ParentStart(_, _) as start, ..tail] ->
      parse_parent_content(tail, start, None, dedent)
    _ -> parse_inverted_section(tokens, dedent)
  }
}

fn parse_parent_content(
  tokens: List(rewriter.Token),
  start: rewriter.Token,
  indentation: Option(String),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  use #(expressions, tail) <- result.try(parse_expressions(tokens, [], dedent))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True -> Ok(#(Some(Parent(start, indentation, expressions)), tail))
  }
}

fn parse_inverted_section(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _), ..] ->
      parse_enclosed(
        tokens,
        parse_inverted_section_opening,
        dedent,
        InvertedSection,
      )
    _ -> parse_section(tokens, dedent)
  }
}

fn parse_inverted_section_opening(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.InvertedSectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_section(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _), ..] ->
      parse_enclosed(tokens, parse_section_opening, dedent, Section)
    _ -> parse_partial(tokens, dedent)
  }
}

fn parse_section_opening(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.SectionStart(_, _) as path, ..tail] -> Ok(#(path, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_closing_tag(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.End(_, _) as end, ..tail] -> Ok(#(end, tail))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn parse_partial(
  tokens: List(rewriter.Token),
  dedent: Option(String),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Padding(_, indentation), rewriter.Partial(_, _) as token, ..tail] ->
      Ok(#(Some(Partial(token, Some(remove_prefix(indentation, dedent)))), tail))
    [rewriter.Partial(_, _) as name, ..tail] -> {
      Ok(#(Some(Partial(name, None)), tail))
    }
    _ -> parse_raw_variable(tokens)
  }
}

fn parse_raw_variable(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.RawVariable(_, _) as path, ..tail] ->
      Ok(emit_expr(RawVariable, path, tail))
    _ -> parse_variable(tokens)
  }
}

fn parse_variable(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Variable(_, _) as path, ..tail] ->
      Ok(emit_expr(Variable, path, tail))

    _ -> parse_primary(tokens)
  }
}

fn parse_primary(
  tokens: List(rewriter.Token),
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Literal(_, _) as value, ..tail] ->
      Ok(#(Some(Literal(value)), tail))
    [rewriter.Eof(_)] -> Ok(#(None, tokens))
    [any, ..] -> Error(UnexpectedTokenError(any))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

// helpers

fn parse_enclosed(
  tokens: List(rewriter.Token),
  opening_rule: fn(List(rewriter.Token)) ->
    Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError),
  dedent: Option(String),
  expr_constructor: fn(rewriter.Token, List(Expression)) -> Expression,
) -> Result(#(Option(Expression), List(rewriter.Token)), SyntaxError) {
  use #(start, tail) <- result.try(opening_rule(tokens))
  use #(expressions, tail) <- result.try(parse_expressions(tail, [], dedent))
  use #(end, tail) <- result.try(parse_closing_tag(tail))
  use start_path <- result.try(tag_path(start))
  use end_path <- result.try(tag_path(end))
  case start_path == end_path {
    False -> Error(NoMatchingEndTagError(start))
    True -> Ok(#(Some(expr_constructor(start, expressions)), tail))
  }
}

fn tag_path(tag: rewriter.Token) -> Result(List(String), SyntaxError) {
  case tag {
    rewriter.SectionStart(_, path) -> Ok(path)
    rewriter.InvertedSectionStart(_, path) -> Ok(path)
    rewriter.End(_, path) -> Ok(path)
    rewriter.BlockStart(_, name) -> Ok([name])
    rewriter.ParentStart(_, name) -> Ok([name])
    any -> Error(UnexpectedTokenError(any))
  }
}

fn parse_eof(
  tokens: List(rewriter.Token),
) -> Result(#(rewriter.Token, List(rewriter.Token)), SyntaxError) {
  case tokens {
    [rewriter.Eof(_) as eof] -> Ok(#(eof, tokens))
    [head, ..] -> Error(UnexpectedTokenError(head))
    [] -> Error(UnexpectedEndOfInputError)
  }
}

fn emit_expr(
  expression: fn(x) -> Expression,
  value: x,
  tail: List(rewriter.Token),
) -> #(Option(Expression), List(rewriter.Token)) {
  #(Some(expression(value)), tail)
}

fn remove_prefix(str: String, prefix: Option(String)) -> String {
  case prefix {
    Some(prefix) -> string.drop_start(str, string.length(prefix))
    None -> str
  }
}

// formatting

pub fn error_to_string(error: SyntaxError) -> String {
  case error {
    UnexpectedTokenError(token) ->
      "line "
      <> int.to_string(token.line)
      <> ": unexpected token: "
      <> rewriter.token_to_string(token)
    UnexpectedEndOfInputError -> "unexpected end of input"
    NoMatchingEndTagError(token) ->
      "line "
      <> int.to_string(token.line)
      <> ": no matching end tag found for start tag: "
      <> rewriter.token_to_string(token)
  }
}
