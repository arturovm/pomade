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
}

fn transduce(tokens: List(scanner.Token)) -> List(Token) {
  transduce_loop(
    tokens,
    True,
    False,
    False,
    None,
    None,
    None,
    None,
    Empty,
    Empty,
  )
}

fn transduce_loop(
  tokens: List(scanner.Token),
  start: Bool,
  standalone: Bool,
  pad: Bool,
  leading: Option(scanner.Token),
  tag: Option(scanner.Token),
  trailing: Option(scanner.Token),
  literal: Option(Token),
  current_line: Tree,
  acc: Tree,
) -> List(Token) {
  case tokens {
    [] -> tree_to_list(acc)
    [scanner.Comment(_), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        tag,
        trailing,
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
        tag,
        trailing,
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
        tag,
        trailing,
        None,
        append_literal(current_line, literal)
          |> append(Variable(line, name)),
        acc,
      )
    [scanner.RawVariable(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        False,
        pad,
        leading,
        tag,
        trailing,
        None,
        append_literal(current_line, literal)
          |> append(RawVariable(line, name)),
        acc,
      )
    [scanner.Text(_, _) as text, ..tail] ->
      transduce_loop(
        tail,
        False,
        False,
        pad,
        leading,
        tag,
        trailing,
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
        tag,
        trailing,
        None,
        append_literal(current_line, literal)
          |> append(SectionStart(line, name)),
        acc,
      )
    [scanner.InvertedSectionStart(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        tag,
        trailing,
        None,
        append_literal(current_line, literal)
          |> append(InvertedSectionStart(line, name)),
        acc,
      )
    [scanner.End(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        pad,
        leading,
        tag,
        trailing,
        None,
        append_literal(current_line, literal) |> append(End(line, name)),
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
            tag,
            trailing,
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
            tag,
            trailing,
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
        tag,
        trailing,
        None,
        append_literal(current_line, literal)
          |> append(Partial(line, name)),
        acc,
      )
    [scanner.BlockStart(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        True,
        leading,
        tag,
        trailing,
        None,
        append_literal(current_line, literal)
          |> append(BlockStart(line, name)),
        acc,
      )
    [scanner.ParentStart(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        start || standalone,
        True,
        leading,
        tag,
        trailing,
        None,
        append_literal(current_line, literal)
          |> append(ParentStart(line, name)),
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
            tag,
            trailing,
            None,
            Empty,
            case pad {
              True -> append_padding(acc, leading) |> append_tree(current_line)
              False -> append_tree(acc, current_line)
            },
          )
        False ->
          transduce_loop(
            tail,
            True,
            False,
            False,
            None,
            tag,
            trailing,
            None,
            Empty,
            acc
              |> append(Indent(line))
              |> append_leading(leading)
              |> append_tree(current_line)
              |> append_literal(glom_literal(literal, nl)),
          )
      }
    }
    [scanner.Eof(line), ..tail] -> {
      let acc = case start, standalone {
        False, False -> append(acc, Indent(line)) |> append_leading(leading)
        True, False -> append_whitespace(acc, leading)
        _, True ->
          case pad {
            True -> append_padding(acc, leading)
            False -> acc
          }
      }
      transduce_loop(
        tail,
        False,
        False,
        False,
        None,
        tag,
        trailing,
        None,
        Empty,
        acc
          |> append_tree(current_line)
          |> append_literal(literal)
          |> append(Eof(line)),
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

fn append_literal(acc: Tree, literal: Option(Token)) -> Tree {
  case literal {
    Some(Literal(_, _) as l) -> append(acc, l)
    _ -> acc
  }
}

fn append_leading(acc: Tree, token: Option(scanner.Token)) -> Tree {
  case token {
    Some(scanner.Whitespace(lexeme, line)) -> append(acc, Leading(lexeme, line))
    _ -> acc
  }
}

fn append_whitespace(acc: Tree, token: Option(scanner.Token)) -> Tree {
  case token {
    Some(scanner.Whitespace(lexeme, line)) -> append(acc, Literal(lexeme, line))
    _ -> acc
  }
}

fn append_padding(acc: Tree, token: Option(scanner.Token)) -> Tree {
  case token {
    Some(scanner.Whitespace(lexeme, line)) -> append(acc, Padding(lexeme, line))
    _ -> acc
  }
}

// tree

type Tree {
  Empty
  Leaf(Token)
  Tree(List(Tree))
}

fn prepend(tree: Tree, prefix: Token) -> Tree {
  append_tree(Leaf(prefix), tree)
}

fn prepend_tree(tree: Tree, prefix: Tree) -> Tree {
  append_tree(prefix, tree)
}

fn append(tree: Tree, suffix: Token) -> Tree {
  append_tree(tree, Leaf(suffix))
}

fn append_tree(tree: Tree, suffix: Tree) -> Tree {
  // We build this in reverse order, because the walk to flatten has to happen
  // in reverse order
  case tree {
    Empty -> suffix
    Tree(tree) -> Tree([suffix, ..tree])
    Leaf(_) -> Tree([suffix, tree])
  }
}

fn tree_to_list(tree: Tree) -> List(Token) {
  flatten([[tree]], [])
}

fn flatten(stack: List(List(Tree)), acc: List(Token)) -> List(Token) {
  case stack {
    [] -> acc
    [[], ..rest] -> flatten(rest, acc)
    [[Empty, ..trees], ..rest] -> flatten([trees, ..rest], acc)
    [[Leaf(token), ..trees], ..rest] -> flatten([trees, ..rest], [token, ..acc])
    [[Tree(inner), ..trees], ..rest] -> flatten([inner, trees, ..rest], acc)
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
