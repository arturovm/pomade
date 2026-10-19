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
  Indent(line: Int)
}

pub type LayoutError {
  UnexpectedToken(scanner.Token)
}

pub fn rewrite(tokens: List(scanner.Token)) -> List(Token) {
  tokens
  |> transduce()
  |> list.reverse()
  |> list.fold([], glom)
  |> list.reverse()
}

fn split_lines(
  tokens: List(scanner.Token),
  lines: List(List(scanner.Token)),
) -> List(List(scanner.Token)) {
  case tokens {
    [] -> list.reverse(lines)
    any -> {
      let #(next_line, tail) = next_line(any, [])
      split_lines(tail, [next_line, ..lines])
    }
  }
}

fn next_line(
  tokens: List(scanner.Token),
  line: List(scanner.Token),
) -> #(List(scanner.Token), List(scanner.Token)) {
  case tokens {
    [] -> #(list.reverse(line), tokens)
    [scanner.Newline(_, _) as nl, ..tail] -> #(
      [nl, ..line] |> list.reverse(),
      tail,
    )
    [any, ..tail] -> next_line(tail, [any, ..line])
  }
}

fn transduce(tokens: List(scanner.Token)) -> List(Token) {
  transduce_loop(tokens, True, False, None, [])
}

fn transduce_loop(
  tokens: List(scanner.Token),
  start: Bool,
  standalone: Bool,
  padding: Option(scanner.Token),
  acc: List(Token),
) -> List(Token) {
  case tokens {
    [] -> acc
    [scanner.Comment(_), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        None,
        insert_whitespace(acc, padding),
      )
    [scanner.SetDelimiters(_, _, _), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        None,
        insert_whitespace(acc, padding),
      )
    [scanner.Variable(line, name), ..tail] ->
      transduce_loop(tail, False, False, None, [
        Variable(line, name),
        ..insert_whitespace(acc, padding)
      ])
    [scanner.RawVariable(line, name), ..tail] ->
      transduce_loop(tail, False, False, None, [
        RawVariable(line, name),
        ..insert_whitespace(acc, padding)
      ])
    [scanner.Text(line, lexeme), ..tail] ->
      transduce_loop(tail, False, False, None, [
        Literal(line, lexeme),
        ..insert_whitespace(acc, padding)
      ])
    [scanner.SectionStart(line, name), ..tail] ->
      transduce_loop(tail, False, start || standalone, None, [
        SectionStart(line, name),
        ..insert_whitespace(acc, padding)
      ])
    [scanner.InvertedSectionStart(line, name), ..tail] ->
      transduce_loop(tail, False, start || standalone, None, [
        InvertedSectionStart(line, name),
        ..insert_whitespace(acc, padding)
      ])
    [scanner.BlockStart(line, name), ..tail] ->
      transduce_loop(tail, False, start || standalone, None, [
        BlockStart(line, name),
        ..insert_whitespace(acc, padding)
      ])
    [scanner.End(line, name), ..tail] ->
      transduce_loop(tail, False, start || standalone, None, [
        End(line, name),
        ..insert_whitespace(acc, padding)
      ])
    [scanner.Whitespace(_, _) as ws, ..tail] ->
      case start {
        True -> transduce_loop(tail, start, standalone, Some(ws), acc)
        False ->
          transduce_loop(tail, start, standalone, None, [
            Literal(ws.line, ws.lexeme),
            ..acc
          ])
      }
    [scanner.Partial(_, _) as p, ..tail] ->
      case start, padding {
        True, Some(scanner.Whitespace(line, lexeme)) ->
          transduce_loop(tail, False, True, None, [
            Partial(p.line, p.name),
            Padding(line, lexeme),
            ..acc
          ])
        _, _ ->
          transduce_loop(tail, start, standalone, padding, [
            Partial(p.line, p.name),
            ..acc
          ])
      }
    [scanner.ParentStart(line, name), ..tail] ->
      case start, padding {
        True, Some(scanner.Whitespace(line, lexeme)) ->
          transduce_loop(tail, False, True, None, [
            ParentStart(line, name),
            Padding(line, lexeme),
            ..acc
          ])
        _, _ ->
          transduce_loop(tail, start, standalone, padding, [
            ParentStart(line, name),
            ..acc
          ])
      }
    [scanner.Newline(line, lexeme), ..tail] ->
      case standalone {
        True ->
          transduce_loop(
            tail,
            True,
            False,
            None,
            insert_whitespace(acc, padding),
          )
        False ->
          transduce_loop(tail, True, False, None, [
            Literal(line, lexeme),
            ..insert_whitespace(acc, padding)
          ])
      }
    [scanner.Eof(line), ..tail] ->
      transduce_loop(tail, False, False, None, [Eof(line), ..acc])
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

fn transform(line: List(scanner.Token)) -> List(Token) {
  case line {
    // base case
    [] -> []
    // standalone comments with newline
    [scanner.Whitespace(_, _), scanner.Comment(_), scanner.Newline(_, _)]
    | [scanner.Comment(_), scanner.Newline(_, _)] -> []
    // standalone comments with eof
    [scanner.Whitespace(_, _), scanner.Comment(_), scanner.Eof(line)]
    | [scanner.Comment(_), scanner.Eof(line)] -> [
      Eof(line),
    ]
    // standalone set delimiters with newline
    [
      scanner.Whitespace(_, _),
      scanner.SetDelimiters(_, _, _),
      scanner.Newline(_, _),
    ]
    | [scanner.SetDelimiters(_, _, _), scanner.Newline(_, _)] -> []

    // standalone set delimiters with eof
    [
      scanner.Whitespace(_, _),
      scanner.SetDelimiters(_, _, _),
      scanner.Eof(line),
    ]
    | [scanner.SetDelimiters(_, _, _), scanner.Eof(line)] -> [
      Eof(line),
    ]
    // standalone section start with newline
    [
      scanner.Whitespace(_, _),
      scanner.SectionStart(line, path),
      scanner.Newline(_, _),
    ]
    | [scanner.SectionStart(line, path), scanner.Newline(_, _)] -> [
      SectionStart(line, path),
    ]
    // standalone section start with eof
    [scanner.Whitespace(_, _), scanner.SectionStart(line, path), scanner.Eof(_)]
    | [scanner.SectionStart(line, path), scanner.Eof(_)] -> [
      SectionStart(line, path),
      Eof(line),
    ]
    // standalone inverted section start with newline
    [scanner.InvertedSectionStart(line, path), scanner.Newline(_, _)]
    | [
        scanner.Whitespace(_, _),
        scanner.InvertedSectionStart(line, path),
        scanner.Newline(_, _),
      ] -> [
      InvertedSectionStart(line, path),
    ]
    // standalone inverted section start with eof
    [
      scanner.Whitespace(_, _),
      scanner.InvertedSectionStart(line, path),
      scanner.Eof(_),
    ]
    | [scanner.InvertedSectionStart(line, path), scanner.Eof(_)] -> [
      InvertedSectionStart(line, path),
      Eof(line),
    ]
    // standalone end tag with newline
    [scanner.Whitespace(_, _), scanner.End(line, path), scanner.Newline(_, _)]
    | [scanner.End(line, path), scanner.Newline(_, _)] -> [
      End(line, path),
    ]
    // standalone end tag with eof
    [scanner.Whitespace(_, _), scanner.End(line, path), scanner.Eof(_)]
    | [scanner.End(line, path), scanner.Eof(_)] -> [
      End(line, path),
      Eof(line),
    ]
    // standalone partial with newline
    [
      scanner.Whitespace(_, ws),
      scanner.Partial(line, name),
      scanner.Newline(_, _),
    ] -> [Padding(line, ws), Partial(line, name)]
    [scanner.Partial(line, name), scanner.Newline(_, _)] -> [
      Padding(line, ""),
      Partial(line, name),
    ]
    // standalone partial with eof
    [scanner.Whitespace(_, ws), scanner.Partial(line, name), scanner.Eof(_)] -> [
      Padding(line, ws),
      Partial(line, name),
      Eof(line),
    ]
    [scanner.Partial(line, name), scanner.Eof(_)] -> [
      //  Padding(line, ""),
      Partial(line, name),
      Eof(line),
    ]
    //standalone block start and end with newline
    [
      scanner.BlockStart(line, name),
      scanner.End(_, path),
      scanner.Newline(_, _),
    ] -> [BlockStart(line, name), End(line, path)]
    //standalone parent start and end with newline
    [
      scanner.ParentStart(line, name),
      scanner.End(_, path),
      scanner.Newline(_, _),
    ] -> [ParentStart(line, name), End(line, path)]
    // end of file
    [scanner.Eof(line)] -> [Eof(line)]
    // continue with in-line rules
    [head, ..tail] -> [Indent(head.line), ..inline([head, ..tail], [])]
  }
}

fn inline(input: List(scanner.Token), output: List(Token)) -> List(Token) {
  case input {
    // base case
    [] -> list.reverse(output)
    // comments
    [scanner.Comment(_), ..tail] -> inline(tail, output)
    // set delimiters
    [scanner.SetDelimiters(_, _, _), ..tail] -> inline(tail, output)
    // other tokens
    [scanner.Text(line, lexeme), ..tail]
    | [scanner.Whitespace(line, lexeme), ..tail]
    | [scanner.Newline(line, lexeme), ..tail] ->
      inline(tail, [Literal(line, lexeme), ..output])
    [scanner.SectionStart(line, path), ..tail] ->
      inline(tail, [SectionStart(line, path), ..output])
    [scanner.InvertedSectionStart(line, path), ..tail] ->
      inline(tail, [InvertedSectionStart(line, path), ..output])
    [scanner.BlockStart(line, path), ..tail] ->
      inline(tail, [BlockStart(line, path), ..output])
    [scanner.ParentStart(line, path), ..tail] ->
      inline(tail, [ParentStart(line, path), ..output])
    [scanner.End(line, path), ..tail] ->
      inline(tail, [End(line, path), ..output])
    [scanner.Partial(line, path), ..tail] ->
      inline(tail, [Partial(line, path), ..output])
    [scanner.RawVariable(line, path), ..tail] ->
      inline(tail, [RawVariable(line, path), ..output])
    [scanner.Variable(line, path), ..tail] ->
      inline(tail, [Variable(line, path), ..output])
    [scanner.Eof(line), ..tail] -> inline(tail, [Eof(line), ..output])
  }
}

fn glom(acc: List(Token), next: Token) -> List(Token) {
  case next {
    Literal(line, literal) -> {
      case acc {
        [Literal(line, value), ..acc_tail] -> [
          Literal(line, value <> literal),
          ..acc_tail
        ]
        acc -> [Literal(line, literal), ..acc]
      }
    }
    any -> [any, ..acc]
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
    Indent(_) -> "LINE_START"
    Eof(_) -> "EOF"
  }
}

fn token_name_with_path(name: String, path: List(String)) -> String {
  name <> "(" <> string.join(path, ".") <> ")"
}
