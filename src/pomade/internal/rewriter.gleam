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
  BlockStart(
    line: Int,
    name: String,
    clearance: Clearance,
    leading: Option(String),
    trailing: Option(String),
  )
  ParentStart(
    line: Int,
    name: String,
    clearance: Clearance,
    leading: Option(String),
    trailing: Option(String),
  )
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

pub type Clearance {
  ClearsBoth
  ClearsStart
  ClearsEnd
  ClearsNone
}

pub fn rewrite(tokens: List(scanner.Token)) -> List(Element) {
  transduce_loop(tokens, True, None, None, None, None, None, Empty, Empty)
}

fn transduce_loop(
  tokens: List(scanner.Token),
  start: Bool,
  leading: Option(String),
  first: Option(scanner.Token),
  latest: Option(scanner.Token),
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
          False -> first
        },
        latest,
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
          False -> first
        },
        latest,
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
        None,
        commit_leading(current_line, line, leading)
          |> commit_first(first)
          |> commit_latest(latest)
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
        None,
        commit_leading(current_line, line, leading)
          |> commit_first(first)
          |> commit_latest(latest)
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
        None,
        glom_literal(literal, lexeme),
        current_line
          |> commit_leading(line, leading)
          |> commit_first(first)
          |> commit_latest(latest)
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
            |> commit_first(first)
            |> commit_latest(latest)
            |> commit_trailing(line, trailing)
            |> append_literal(line, literal)
            |> append(SectionStart(line, name)),
        )
      }
      transduce_loop(
        tail,
        False,
        leading,
        tag,
        None,
        None,
        None,
        current_line,
        acc,
      )
    }
    [scanner.InvertedSectionStart(line, name) as iss, ..tail] -> {
      let #(leading, tag, current_line) = case start {
        True -> #(leading, Some(iss), current_line)
        False -> #(
          None,
          None,
          commit_leading(current_line, line, leading)
            |> commit_first(first)
            |> commit_latest(latest)
            |> commit_trailing(line, trailing)
            |> append_literal(line, literal)
            |> append(InvertedSectionStart(line, name)),
        )
      }
      transduce_loop(
        tail,
        False,
        leading,
        tag,
        None,
        None,
        None,
        current_line,
        acc,
      )
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
            None,
            commit_leading(current_line, line, leading)
              |> commit_first(first)
              |> commit_latest(latest)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal)
              |> append(End(line, name, None)),
            acc,
          )
      }
    [scanner.Whitespace(_, lexeme), ..tail] -> {
      let #(leading, trailing, literal) = case start, first, latest {
        // if we are at line start, then whitespace is considered leading
        True, _, _ -> #(Some(lexeme), None, None)
        // if we are no longer at line start and there's a previous tag in the
        // tag variable, whitespace is treated as a possible trailing value,
        // plus we keep the leading variable as is, in case this is a "normal"
        // standalone tag (i.e. not a block or a parent, which have a newer
        // whitespace model)
        _, Some(_), _ | _, _, Some(_) -> #(leading, Some(lexeme), None)
        // otherwise, it's treated as a literal
        _, None, _ -> #(None, None, glom_literal(literal, lexeme))
      }
      transduce_loop(
        tail,
        start,
        leading,
        first,
        latest,
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
            None,
            commit_leading(current_line, line, leading)
              |> commit_first(first)
              |> commit_latest(latest)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal)
              |> append(Partial(line, name, None)),
            acc,
          )
      }
    [scanner.BlockStart(line, _) as bs, ..tail] ->
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
            Some(bs),
            None,
            None,
            commit_leading(current_line, line, leading)
              |> commit_first(first)
              |> commit_latest(latest)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal),
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
            Some(ps),
            None,
            None,
            commit_leading(current_line, line, leading)
              |> commit_first(first)
              |> commit_latest(latest)
              |> commit_trailing(line, trailing)
              |> append_literal(line, literal),
            acc,
          )
      }
    [scanner.Newline(line, lexeme), ..tail] -> {
      let acc = case first, latest {
        // standalone elided
        Some(scanner.Comment(_)), _ | Some(scanner.SetDelimiters(_, _, _)), _ ->
          acc
        // standalone tags
        Some(scanner.SectionStart(_, _)), _
        | Some(scanner.InvertedSectionStart(_, _)), _
        | Some(scanner.End(_, _)), _
        -> commit_first(acc, first)
        // partials
        Some(scanner.Partial(_, name)), _ ->
          append(acc, Partial(line, name, leading))
        // blocks
        Some(scanner.BlockStart(_, name)), _ ->
          // if the first tag was pending to be committed, then that means that
          // the line is empty, aside from the block start, so the tag clears
          // both, and there's no need to write the current line into the main
          // accumulator
          append(acc, BlockStart(line, name, ClearsBoth, leading, trailing))
        _, Some(scanner.BlockStart(_, name)) ->
          // if the latest tag was pending to be committed, then that means that
          // the line is NOT empty, so the tag only clears the end, and we
          // absorb the trailing whitespace into the element
          append(acc, Indent(line))
          |> append_tree(current_line)
          |> append(BlockStart(
            line,
            name,
            ClearsEnd,
            leading,
            glom_literal(trailing, lexeme),
          ))
        // parents
        Some(scanner.ParentStart(_, name)), _ ->
          // all of the same logic above applies to parents
          append(acc, ParentStart(line, name, ClearsBoth, leading, trailing))
        _, Some(scanner.ParentStart(_, name)) ->
          // all of the same logic above applies to parents
          append(acc, Indent(line))
          |> append_tree(current_line)
          |> append(ParentStart(
            line,
            name,
            ClearsEnd,
            leading,
            glom_literal(trailing, lexeme),
          ))
        // content lines
        _, _ ->
          acc
          |> append(Indent(line))
          |> append_tree(current_line)
          |> append_literal(line, glom_literal(literal, lexeme))
      }
      transduce_loop(tail, True, None, None, None, None, None, Empty, acc)
    }
    [scanner.Eof(line), ..tail] -> {
      let acc = case first, latest {
        // standalone elided
        Some(scanner.Comment(_)), _ | Some(scanner.SetDelimiters(_, _, _)), _ ->
          acc
        // standalone tags
        Some(scanner.SectionStart(_, _)), _
        | Some(scanner.InvertedSectionStart(_, _)), _
        | Some(scanner.End(_, _)), _
        -> commit_first(acc, first)
        // partials
        Some(scanner.Partial(_, name)), _ ->
          append(acc, Partial(line, name, leading))
        // blocks
        Some(scanner.BlockStart(_, name)), _ ->
          // if the first tag was pending to be committed, then that means that
          // the line is empty, aside from the block start, so the tag clears
          // both, and there's no need to write the current line into the main
          // accumulator
          append(acc, BlockStart(line, name, ClearsBoth, leading, trailing))
        // if the latest tag was pending to be committed, then that means that the
        // line is NOT empty, so the tag only clears the end
        _, Some(scanner.BlockStart(_, name)) ->
          append(acc, Indent(line))
          |> append_tree(current_line)
          |> append(BlockStart(line, name, ClearsEnd, leading, trailing))
        // parents
        Some(scanner.ParentStart(_, name)), _ ->
          // all of the same logic above applies to parents
          append(acc, ParentStart(line, name, ClearsBoth, leading, trailing))
        _, Some(scanner.ParentStart(_, name)) ->
          // all of the same logic above applies to parents
          append(acc, Indent(line))
          |> append_tree(current_line)
          |> append(ParentStart(line, name, ClearsEnd, leading, trailing))
        // content lines
        _, _ ->
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

// commit the first tag inline
fn commit_first(acc: Tree, tag: Option(scanner.Token)) -> Tree {
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
      // we know that the block start tag clears the start, because if it is
      // being committed, that means it was the first tag seen on the line, and
      // now it isn't
      append(acc, BlockStart(line, name, ClearsStart, None, None))
    // parent start
    Some(scanner.ParentStart(line, name)) ->
      // all of the same logic above applies to parents
      append(acc, ParentStart(line, name, ClearsStart, None, None))
    // all other cases
    _ -> acc
  }
}

// commit the latest tag inline
fn commit_latest(acc: Tree, tag: Option(scanner.Token)) -> Tree {
  case tag {
    // block start
    Some(scanner.BlockStart(line, name)) ->
      // we know that the block start tag clears none, because if it is being
      // committed, that means it was the latest tag seen on the line, and now
      // it isn't
      append(acc, BlockStart(line, name, ClearsNone, None, None))
    // parent start
    Some(scanner.ParentStart(line, name)) ->
      // all of the same logic above applies to parents
      append(acc, ParentStart(line, name, ClearsNone, None, None))
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
    BlockStart(_, name, _, _, _) -> token_name_with_path("BLOCK_START", [name])
    ParentStart(_, name, _, _, _) ->
      token_name_with_path("PARENT_START", [name])
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
