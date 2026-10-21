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

import gleam/option.{type Option, None, Some}
import gleam/string

import pomade/internal/scanner

pub type Element {
  // general text
  Literal(line: Int, lexeme: String)
  // tags
  SectionStart(line: Int, name: List(String))
  InvertedSectionStart(line: Int, name: List(String))
  BlockStart(line: Int, name: String, leading: Option(String))
  ParentStart(line: Int, name: String, leading: Option(String))
  End(line: Int, name: List(String), trailing: Option(String))
  Partial(line: Int, name: scanner.PartialName, leading: Option(String))
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

pub fn rewrite(tokens: List(scanner.Token)) -> List(Element) {
  transduce_loop(tokens, True, None, None, None, None, Empty, Empty)
}

fn transduce_loop(
  tokens: List(scanner.Token),
  start: Bool,
  leading: Option(String),
  tag: Option(scanner.Token),
  trailing: Option(String),
  literal: Option(String),
  current_line: Tree,
  acc: Tree,
) -> List(Element) {
  case tokens {
    [] -> tree_to_list(acc)
    [scanner.Comment(_) as comment, ..tail] ->
      transduce_loop(
        tail,
        False,
        leading,
        case start {
          True -> Some(comment)
          False -> tag
        },
        trailing,
        literal,
        current_line,
        acc,
      )
    [scanner.SetDelimiters(_, _, _) as sd, ..tail] ->
      transduce_loop(
        tail,
        False,
        leading,
        case start {
          True -> Some(sd)
          False -> tag
        },
        trailing,
        literal,
        current_line,
        acc,
      )
    [scanner.Variable(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        None,
        None,
        None,
        None,
        commit_leading(current_line, line, leading)
          |> commit_tag(tag)
          |> commit_trailing(line, trailing)
          |> append_literal(line, literal)
          |> append(Variable(line, name)),
        acc,
      )
    [scanner.RawVariable(line, name), ..tail] ->
      transduce_loop(
        tail,
        False,
        None,
        None,
        None,
        None,
        commit_leading(current_line, line, leading)
          |> commit_tag(tag)
          |> commit_trailing(line, trailing)
          |> append_literal(line, literal)
          |> append(RawVariable(line, name)),
        acc,
      )
    [scanner.Text(line, lexeme), ..tail] ->
      transduce_loop(
        tail,
        False,
        None,
        None,
        None,
        glom_literal(literal, lexeme),
        current_line
          |> commit_leading(line, leading)
          |> commit_tag(tag)
          |> commit_trailing(line, trailing),
        acc,
      )
    [scanner.SectionStart(line, name) as ss, ..tail] -> {
      let #(leading, tag, current_line) = case start {
        True -> #(leading, Some(ss), current_line)
        False -> #(
          None,
          None,
          commit_leading(current_line, line, leading)
            |> commit_tag(tag)
            |> commit_trailing(line, trailing)
            |> append_literal(line, literal)
            |> append(SectionStart(line, name)),
        )
      }
      transduce_loop(tail, False, leading, tag, None, None, current_line, acc)
    }
    [scanner.InvertedSectionStart(line, name) as iss, ..tail] -> {
      let #(leading, tag, current_line) = case start {
        True -> #(leading, Some(iss), current_line)
        False -> #(
          None,
          None,
          commit_leading(current_line, line, leading)
            |> commit_tag(tag)
            |> commit_trailing(line, trailing)
            |> append_literal(line, literal)
            |> append(InvertedSectionStart(line, name)),
        )
      }
      transduce_loop(tail, False, leading, tag, None, None, current_line, acc)
    }
    [scanner.End(line, name) as end, ..tail] ->
      case start {
        True ->
          transduce_loop(
            tail,
            False,
            leading,
            Some(end),
            None,
            None,
            current_line,
            acc,
          )
        False ->
          transduce_loop(
            tail,
            False,
            None,
            None,
            None,
            None,
            commit_leading(current_line, line, leading)
              |> commit_tag(tag)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal)
              |> append(End(line, name, None)),
            acc,
          )
      }
    [scanner.Whitespace(_, lexeme), ..tail] -> {
      let #(leading, trailing, literal) = case start, tag {
        // if we are at line start, then whitespace is considered leading
        True, _ -> #(Some(lexeme), None, None)
        // if there's a previous tag in the tag variable, whitespace is treated
        // as a possible trailing value
        _, Some(_) -> #(None, Some(lexeme), None)
        // otherwise, it's treated as a literal
        _, None -> #(None, None, glom_literal(literal, lexeme))
      }
      transduce_loop(
        tail,
        start,
        leading,
        tag,
        trailing,
        literal,
        current_line,
        acc,
      )
    }
    [scanner.Partial(line, name) as partial, ..tail] ->
      case start {
        True ->
          transduce_loop(
            tail,
            False,
            leading,
            Some(partial),
            None,
            None,
            current_line,
            acc,
          )
        False ->
          transduce_loop(
            tail,
            False,
            None,
            None,
            None,
            None,
            commit_leading(current_line, line, leading)
              |> commit_tag(tag)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal)
              |> append(Partial(line, name, None)),
            acc,
          )
      }
    [scanner.BlockStart(line, name) as bs, ..tail] ->
      case start {
        True ->
          transduce_loop(
            tail,
            False,
            leading,
            Some(bs),
            // lol
            None,
            None,
            current_line,
            acc,
          )
        False ->
          transduce_loop(
            tail,
            False,
            leading,
            None,
            None,
            None,
            commit_leading(current_line, line, leading)
              |> commit_tag(tag)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal)
              |> append(BlockStart(line, name, None)),
            acc,
          )
      }
    [scanner.ParentStart(line, name) as ps, ..tail] ->
      case start {
        True ->
          transduce_loop(
            tail,
            False,
            leading,
            Some(ps),
            None,
            None,
            current_line,
            acc,
          )
        False ->
          transduce_loop(
            tail,
            False,
            leading,
            None,
            None,
            None,
            commit_leading(current_line, line, leading)
              |> commit_tag(tag)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal)
              |> append(ParentStart(line, name, None)),
            acc,
          )
      }
    [scanner.Newline(line, lexeme), ..tail] -> {
      let acc = case tag {
        // standalone elided
        Some(scanner.Comment(_)) | Some(scanner.SetDelimiters(_, _, _)) -> acc
        // standalone tags
        Some(scanner.SectionStart(_, _))
        | Some(scanner.InvertedSectionStart(_, _))
        | Some(scanner.End(_, _))
        | Some(scanner.BlockStart(_, _))
        | Some(scanner.ParentStart(_, _)) -> commit_tag(acc, tag)
        // partials
        Some(scanner.Partial(_, name)) ->
          append(acc, Partial(line, name, leading))
        // content lines
        _ ->
          acc
          |> append(Indent(line))
          |> append_tree(current_line)
          |> commit_leading(line, leading)
          |> commit_tag(tag)
          |> commit_trailing(line, trailing)
          |> append_literal(line, glom_literal(literal, lexeme))
      }
      transduce_loop(tail, True, None, None, None, None, Empty, acc)
    }
    [scanner.Eof(line), ..tail] -> {
      let acc = case tag {
        // standalone elided
        Some(scanner.Comment(_)) | Some(scanner.SetDelimiters(_, _, _)) -> acc
        // standalone tags
        Some(scanner.SectionStart(_, _))
        | Some(scanner.InvertedSectionStart(_, _))
        | Some(scanner.End(_, _))
        | Some(scanner.BlockStart(_, _))
        | Some(scanner.ParentStart(_, _)) -> commit_tag(acc, tag)
        // partials
        Some(scanner.Partial(_, name)) ->
          append(acc, Partial(line, name, leading))
        // content llines
        _ ->
          case start {
            // if the line is empty and there's leading whitespace, we append
            // it as a literal, and we don't insert the indentation marker
            True -> append_whitespace(acc, line, leading)
            // if the line is not empty, we treat it as a regular content line
            False ->
              acc
              |> append(Indent(line))
              |> append_tree(current_line)
              |> append_literal(line, literal)
          }
      }
      transduce_loop(
        tail,
        True,
        None,
        None,
        None,
        None,
        Empty,
        acc
          |> append(Eof(line)),
      )
    }
  }
}

fn commit_leading(acc: Tree, line: Int, leading: Option(String)) -> Tree {
  case leading {
    Some(leading) -> append(acc, Leading(line, leading))
    None -> acc
  }
}

// commit tag inline
fn commit_tag(acc: Tree, tag: Option(scanner.Token)) -> Tree {
  case tag {
    // elided tags
    Some(scanner.Comment(_)) | Some(scanner.SetDelimiters(_, _, _)) -> acc
    // section start
    Some(scanner.SectionStart(line, name)) ->
      append(acc, SectionStart(line, name))
    // inverted section start
    Some(scanner.InvertedSectionStart(line, name)) ->
      append(acc, InvertedSectionStart(line, name))
    // end
    Some(scanner.End(line, name)) -> append(acc, End(line, name, None))
    // partial
    Some(scanner.Partial(line, name)) -> append(acc, Partial(line, name, None))
    // block start
    Some(scanner.BlockStart(line, name)) ->
      append(acc, BlockStart(line, name, None))
    // parent start
    Some(scanner.ParentStart(line, name)) ->
      append(acc, ParentStart(line, name, None))
    // all other cases
    _ -> acc
  }
}

fn commit_trailing(acc: Tree, line: Int, trailing: Option(String)) -> Tree {
  case trailing {
    Some(trailing) -> append(acc, Literal(line, trailing))
    None -> acc
  }
}

fn glom_literal(literal: Option(String), token: String) -> Option(String) {
  case literal, token {
    None, lexeme -> Some(lexeme)
    Some(literal), lexeme -> Some(literal <> lexeme)
  }
}

fn append_literal(acc: Tree, line: Int, literal: Option(String)) -> Tree {
  case literal {
    Some(l) -> append(acc, Literal(line, l))
    _ -> acc
  }
}

fn append_leading(acc: Tree, line: Int, token: Option(String)) -> Tree {
  case token {
    Some(lexeme) -> append(acc, Leading(line, lexeme))
    _ -> acc
  }
}

fn append_whitespace(acc: Tree, line: Int, token: Option(String)) -> Tree {
  case token {
    Some(lexeme) -> append(acc, Literal(line, lexeme))
    _ -> acc
  }
}

fn append_padding(acc: Tree, line: Int, token: Option(String)) -> Tree {
  case token {
    Some(lexeme) -> append(acc, Padding(line, lexeme))
    _ -> acc
  }
}

// tree

type Tree {
  Empty
  Leaf(Element)
  Tree(List(Tree))
}

fn prepend(tree: Tree, prefix: Element) -> Tree {
  append_tree(Leaf(prefix), tree)
}

fn prepend_tree(tree: Tree, prefix: Tree) -> Tree {
  append_tree(prefix, tree)
}

fn append(tree: Tree, suffix: Element) -> Tree {
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

fn tree_to_list(tree: Tree) -> List(Element) {
  flatten([[tree]], [])
}

fn flatten(stack: List(List(Tree)), acc: List(Element)) -> List(Element) {
  case stack {
    [] -> acc
    [[], ..rest] -> flatten(rest, acc)
    [[Empty, ..trees], ..rest] -> flatten([trees, ..rest], acc)
    [[Leaf(token), ..trees], ..rest] -> flatten([trees, ..rest], [token, ..acc])
    [[Tree(inner), ..trees], ..rest] -> flatten([inner, trees, ..rest], acc)
  }
}

// formatting

pub fn token_to_string(token: Element) -> String {
  case token {
    Literal(_, _) -> "LITERAL"
    SectionStart(_, path) -> token_name_with_path("SECTION_START", path)
    InvertedSectionStart(_, path) ->
      token_name_with_path("INVERTED_SECTION_START", path)
    BlockStart(_, name, _) -> token_name_with_path("BLOCK_START", [name])
    ParentStart(_, name, _) -> token_name_with_path("PARENT_START", [name])
    End(_, path, _) -> token_name_with_path("END_TAG", path)
    Partial(_, name, _) ->
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
