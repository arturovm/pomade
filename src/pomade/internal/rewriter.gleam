//// Rewrite rules for Mustache:
////
//// _line  -> ( [WHITESPACE] COMMENT NEWLINE                => empty
////           | [WHITESPACE] COMMENT EOF                    => EOF
////           | [WHITESPACE] SET_DELIMITERS NEWLINE         => empty
////           | [WHITESPACE] SET_DELIMITERS EOF             => EOF
////           | [WHITESPACE] SECTION_START NEWLINE          => SECTION_START
////           | [WHITESPACE] SECTION_START EOF              => SECTION_START EOF
////           | [WHITESPACE] INVERTED_SECTION_START NEWLINE => INVERTED_SECTION_START
////           | [WHITESPACE] INVERTED_SECTION_START EOF     => INVERTED_SECTION_START EOF
////           | [WHITESPACE] END NEWLINE                    => END
////           | [WHITESPACE] END EOF                        => END EOF
////           | [WHITESPACE] PARTIAL NEWLINE                => PADDING PARTIAL
////           | [WHITESPACE] PARTIAL EOF                    => PADDING PARTIAL EOF
////           | PARENT_START END NEWLINE                    => PARENT_START END
////           | EOF                                         => EOF )
////           / {_token}                                    => INDENT {_token} ;
//// _token -> ( COMMENT                                     => empty
////           | SET_DELIMITERS                              => empty
////           | TEXT                                        => LITERAL
////           | WHITESPACE                                  => LITERAL
////           | NEWLINE                                     => LITERAL
////           | SECTION_START                               => SECTION_START
////           | INVERTED_SECTION_START                      => INVERTED_SECTION_START
////           | END                                         => END
////           | PARTIAL                                     => PARTIAL
////           | RAW_VARIABLE                                => RAW_VARIABLE
////           | VARIABLE                                    => VARIABLE
////           | EOF                                         => EOF ) ;

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import pomade/internal/scanner

pub type Token {
  // general text
  Literal(line: Int, lexeme: String)
  // tags
  SectionStart(line: Int, name: List(String))
  InvertedSectionStart(line: Int, name: List(String))
  BlockStart(line: Int, name: String)
  ParentStart(line: Int, name: String)
  End(line: Int, name: List(String))
  Partial(line: Int, name: scanner.PartialName)
  RawVariable(line: Int, name: List(String))
  Variable(line: Int, name: List(String))
  // eof
  Eof(line: Int)
  // synthetic tokens
  Padding(line: Int, lexeme: String)
  Leading(line: Int, lexeme: String)
  Indent(line: Int)
}

pub type LayoutError {
  UnexpectedToken(scanner.Token)
}

pub fn rewrite(tokens: List(scanner.Token)) -> List(Token) {
  tokens
  |> transduce()
  |> list.reverse()
}

fn transduce(tokens: List(scanner.Token)) -> List(Token) {
  transduce_loop(tokens, True, False, False, None, None, [], [])
}

fn transduce_loop(
  tokens: List(scanner.Token),
  start: Bool,
  standalone: Bool,
  pad: Bool,
  leading: Option(scanner.Token),
  literal: Option(Token),
  current_line: List(Token),
  acc: List(Token),
) -> List(Token) {
  case tokens {
    [] -> acc
    [scanner.Comment(_), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        literal,
        current_line,
        acc,
      )
    [scanner.SetDelimiters(_, _, _), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        literal,
        current_line,
        acc,
      )
    [scanner.Variable(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        False,
        pad,
        leading,
        None,
        [Variable(line, name), ..insert_literal(current_line, literal)],
        acc,
      )
    [scanner.RawVariable(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        False,
        pad,
        leading,
        None,
        [RawVariable(line, name), ..insert_literal(current_line, literal)],
        acc,
      )
    [scanner.Text(_, _) as text, ..tail] ->
      transduce_loop(
        tail,
        False,
        False,
        pad,
        leading,
        glom_literal(literal, text),
        current_line,
        acc,
      )
    [scanner.SectionStart(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        None,
        [SectionStart(line, name), ..insert_literal(current_line, literal)],
        acc,
      )
    [scanner.InvertedSectionStart(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        None,
        [
          InvertedSectionStart(line, name),
          ..insert_literal(current_line, literal)
        ],
        acc,
      )
    [scanner.End(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        None,
        [End(line, name), ..insert_literal(current_line, literal)],
        acc,
      )
    [scanner.Whitespace(_, _) as ws, ..tail] ->
      case start {
        True ->
          transduce_loop(
            tail,
            True,
            False,
            False,
            Some(ws),
            None,
            current_line,
            acc,
          )
        False ->
          transduce_loop(
            tail,
            False,
            False,
            False,
            leading,
            glom_literal(literal, ws),
            current_line,
            acc,
          )
      }
    [scanner.Partial(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        True,
        leading,
        None,
        [Partial(line, name), ..insert_literal(current_line, literal)],
        acc,
      )
    [scanner.BlockStart(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        True,
        leading,
        None,
        [BlockStart(line, name), ..insert_literal(current_line, literal)],
        acc,
      )
    [scanner.ParentStart(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        True,
        leading,
        None,
        [ParentStart(line, name), ..insert_literal(current_line, literal)],
        acc,
      )
    [scanner.Newline(line, _) as nl, ..tail] -> {
      case standalone {
        True ->
          transduce_loop(
            tail,
            True,
            False,
            False,
            None,
            None,
            [],
            list.append(current_line, case pad {
              True -> insert_padding(acc, leading)
              False -> acc
            }),
          )
        False ->
          transduce_loop(
            tail,
            True,
            False,
            False,
            None,
            None,
            [],
            list.append(
              insert_literal(current_line, glom_literal(literal, nl)),
              insert_leading([Indent(line), ..acc], leading),
            ),
          )
      }
    }
    [scanner.Eof(line), ..tail] -> {
      let acc = case start, standalone {
        False, False -> insert_leading([Indent(line), ..acc], leading)
        True, False -> insert_whitespace(acc, leading)
        _, True ->
          case pad {
            True -> insert_padding(acc, leading)
            False -> acc
          }
      }
      transduce_loop(
        tail,
        False,
        False,
        False,
        None,
        None,
        [],
        list.append([Eof(line), ..insert_literal(current_line, literal)], acc),
      )
    }
  }
}

fn glom_literal(literal: Option(Token), token: scanner.Token) -> Option(Token) {
  case literal, token {
    None, scanner.Whitespace(line, lexeme)
    | None, scanner.Text(line, lexeme)
    | None, scanner.Newline(line, lexeme)
    -> Some(Literal(line, lexeme))
    Some(Literal(line, literal)), scanner.Whitespace(_, lexeme)
    | Some(Literal(line, literal)), scanner.Text(_, lexeme)
    | Some(Literal(line, literal)), scanner.Newline(_, lexeme)
    -> Some(Literal(line, literal <> lexeme))
    _, _ -> None
  }
}

fn insert_literal(acc: List(Token), literal: Option(Token)) -> List(Token) {
  case literal {
    Some(Literal(_, _) as l) -> [l, ..acc]
    _ -> acc
  }
}

fn insert_leading(
  acc: List(Token),
  token: Option(scanner.Token),
) -> List(Token) {
  case token {
    Some(scanner.Whitespace(lexeme, line)) -> [Leading(lexeme, line), ..acc]
    _ -> acc
  }
}

fn insert_whitespace(
  acc: List(Token),
  token: Option(scanner.Token),
) -> List(Token) {
  case token {
    Some(scanner.Whitespace(lexeme, line)) -> [Literal(lexeme, line), ..acc]
    _ -> acc
  }
}

fn insert_padding(
  acc: List(Token),
  token: Option(scanner.Token),
) -> List(Token) {
  case token {
    Some(scanner.Whitespace(lexeme, line)) -> [Padding(lexeme, line), ..acc]
    _ -> acc
  }
}

// formatting

pub fn token_to_string(token: Token) -> String {
  case token {
    Literal(_, _) -> "LITERAL"
    SectionStart(_, path) -> token_name_with_path("SECTION_START", path)
    InvertedSectionStart(_, path) ->
      token_name_with_path("INVERTED_SECTION_START", path)
    BlockStart(_, name) -> token_name_with_path("BLOCK_START", [name])
    ParentStart(_, name) -> token_name_with_path("PARENT_START", [name])
    End(_, path) -> token_name_with_path("END_TAG", path)
    Partial(_, name) ->
      token_name_with_path("PARTIAL", case name {
        scanner.StaticName(name) -> [name]
        scanner.DynamicName(path) -> path
      })
    RawVariable(_, path) -> token_name_with_path("RAW_VARIABLE", path)
    Variable(_, path) -> token_name_with_path("VARIABLE", path)
    Padding(_, _) -> "PADDING"
    Indent(_) -> "INDENT"
    Leading(_, _) -> "LEADING"
    Eof(_) -> "EOF"
  }
}

fn token_name_with_path(name: String, path: List(String)) -> String {
  name <> "(" <> string.join(path, ".") <> ")"
}
