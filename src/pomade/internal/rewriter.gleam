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
  // output tags
  Variable(line: Int, name: List(String))
  RawVariable(line: Int, name: List(String))
  // non-output tags
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
  End(
    line: Int,
    name: List(String),
    clearance: Clearance,
    leading: Option(String),
    trailing: Option(String),
  )
  Partial(line: Int, name: scanner.PartialName, leading: Option(String))
  // eof
  Eof(line: Int)
  // synthetic tokens
  Leading(line: Int, lexeme: String)
  Indent(line: Int)
}

pub type Clearance {
  ClearsBoth
  ClearsStart
  ClearsEnd
  ClearsNone
}

type State {
  LineStart(leading: Option(String))
  TagPending(TagPendingData)
  Content(current_line: Tree, literal: Option(String))
}

type TagPendingData {
  FirstTag(leading: Option(String), tag: NonOutputTag, trailing: Option(String))
  InlineTag(current_line: Tree, tag: NonOutputTag, trailing: Option(String))
}

type NonOutputTag {
  SectionStartTag(line: Int, name: List(String))
  InvertedSectionStartTag(line: Int, name: List(String))
  BlockStartTag(line: Int, name: String)
  ParentStartTag(line: Int, name: String)
  EndTag(line: Int, name: List(String))
  PartialTag(line: Int, name: scanner.PartialName)
  ElidedTag(line: Int)
}

pub fn rewrite(tokens: List(scanner.Token)) -> List(Element) {
  transduce_loop(tokens, LineStart(None), Empty)
}

// This is (my practical implementation of a) Streaming Data String Transducer,
// (https://www.cis.upenn.edu/~alur/Popl11.pdf) which is a specialized form of
// transducer that translates its input alphabet into the output alphabet in a
// single pass, in O(n) and without "copying." Given the kinds of
// transformations Mustache requires to implement the canonical whitespace
// model, these are very desirable properties.
//
// It operates as a sort of tape head that can "remember" and store values in
// "buffers" and use them as inputs to calculate the next state and values of
// the transducer.
//
// The variables of an SDST are formally defined in the paper to be of the input
// data type, of a tag type (a type variant), booleans, or sub-strings of data
// values. The possible states of the transducer are calculated from the
// boolean and tag variables that the transducer keeps track of. I initially
// tried to implement it exactly as the paper describes but, after making a
// freaking mess, I decided to take a lesson from Scott Wlaschin
// (https://fsharpforfunandprofit.com) and reify the concepts in the paper as a
// sort of hybrid representation of the possible states and the variables of
// the transducer, for which I used the `State` type above.
fn transduce_loop(
  tokens: List(scanner.Token),
  state: State,
  acc: Tree,
) -> List(Element) {
  case tokens {
    [] -> tree_to_list(acc)
    [scanner.Comment(line), ..tail] ->
      transduce_loop(
        tail,
        case state {
          LineStart(leading) ->
            TagPending(FirstTag(leading, ElidedTag(line), None))
          _ -> state
        },
        acc,
      )
    [scanner.SetDelimiters(line, _, _), ..tail] ->
      transduce_loop(
        tail,
        case state {
          LineStart(leading) ->
            TagPending(FirstTag(leading, ElidedTag(line), None))
          _ -> state
        },
        acc,
      )
    [scanner.Variable(line, name), ..tail] -> {
      let next_state =
        Content(
          commit_pending(state, line) |> append(Variable(line, name)),
          None,
        )
      transduce_loop(tail, next_state, acc)
    }
    [scanner.RawVariable(line, name), ..tail] -> {
      let next_state =
        Content(
          commit_pending(state, line) |> append(RawVariable(line, name)),
          None,
        )
      transduce_loop(tail, next_state, acc)
    }
    [scanner.Text(line, lexeme), ..tail] -> {
      let next_state = case state {
        Content(current_line, literal) ->
          Content(current_line, glom_literal(literal, lexeme))
        state -> Content(commit_pending(state, line), Some(lexeme))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.SectionStart(line, name), ..tail] -> {
      let next_state = case state {
        LineStart(leading) ->
          TagPending(FirstTag(leading, SectionStartTag(line, name), None))
        TagPending(_) | Content(_, _) ->
          TagPending(InlineTag(
            commit_pending(state, line),
            SectionStartTag(line, name),
            None,
          ))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.InvertedSectionStart(line, name), ..tail] -> {
      let next_state = case state {
        LineStart(leading) ->
          TagPending(FirstTag(
            leading,
            InvertedSectionStartTag(line, name),
            None,
          ))
        TagPending(_) | Content(_, _) ->
          TagPending(InlineTag(
            commit_pending(state, line),
            InvertedSectionStartTag(line, name),
            None,
          ))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.End(line, name), ..tail] -> {
      let next_state = case state {
        LineStart(leading) ->
          TagPending(FirstTag(leading, EndTag(line, name), None))
        TagPending(_) | Content(_, _) ->
          TagPending(InlineTag(
            commit_pending(state, line),
            EndTag(line, name),
            None,
          ))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.Whitespace(_, lexeme), ..tail] -> {
      let next_state = case state {
        // if we are at line start, then whitespace is considered leading
        LineStart(_) -> LineStart(Some(lexeme))
        // if we are no longer at line start and there's a previous tag in
        // the first tag variable, whitespace is treated as a possible trailing
        // value, plus we keep the existing trailing variable as is, in case the
        // SST has presviously seen whitespace and then passed a comment tag
        TagPending(FirstTag(leading, tag, trailing)) ->
          TagPending(FirstTag(leading, tag, glom_literal(trailing, lexeme)))
        // as above
        TagPending(InlineTag(current_line, tag, trailing)) ->
          TagPending(InlineTag(
            current_line,
            tag,
            glom_literal(trailing, lexeme),
          ))
        // otherwise, it's treated as a literal
        Content(current_line, literal) ->
          Content(current_line, glom_literal(literal, lexeme))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.Partial(line, name), ..tail] -> {
      let next_state = case state {
        LineStart(leading) ->
          TagPending(FirstTag(leading, PartialTag(line, name), None))
        TagPending(_) | Content(_, _) ->
          TagPending(InlineTag(
            commit_pending(state, line),
            PartialTag(line, name),
            None,
          ))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.BlockStart(line, name), ..tail] -> {
      let next_state = case state {
        LineStart(leading) ->
          TagPending(FirstTag(leading, BlockStartTag(line, name), None))
        TagPending(_) | Content(_, _) ->
          TagPending(InlineTag(
            commit_pending(state, line),
            BlockStartTag(line, name),
            None,
          ))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.ParentStart(line, name), ..tail] -> {
      let next_state = case state {
        LineStart(leading) ->
          TagPending(FirstTag(leading, ParentStartTag(line, name), None))
        TagPending(_) | Content(_, _) ->
          TagPending(InlineTag(
            commit_pending(state, line),
            ParentStartTag(line, name),
            None,
          ))
      }
      transduce_loop(tail, next_state, acc)
    }
    [scanner.Newline(line, lexeme), ..tail] -> {
      let acc = end_line(acc, state, line, Some(lexeme))
      transduce_loop(tail, LineStart(None), acc)
    }
    [scanner.Eof(line), ..tail] -> {
      let acc = end_line(acc, state, line, None)
      transduce_loop(tail, LineStart(None), append(acc, Eof(line)))
    }
  }
}

fn commit_pending(state: State, line: Int) -> Tree {
  case state {
    LineStart(leading) -> commit_leading(Empty, line, leading)
    TagPending(FirstTag(leading, tag, trailing)) ->
      commit_tag(Empty, leading, tag, trailing, ClearsStart)
    TagPending(InlineTag(current_line, tag, trailing)) ->
      commit_tag(current_line, None, tag, trailing, ClearsNone)
    Content(current_line, literal) ->
      append_literal(current_line, line, literal)
  }
}

fn commit_tag(
  acc: Tree,
  leading: Option(String),
  tag: NonOutputTag,
  trailing: Option(String),
  clearance: Clearance,
) -> Tree {
  case tag, clearance {
    // standalone elided
    ElidedTag(_), ClearsBoth -> acc
    // all other elided cases
    ElidedTag(line), _ ->
      commit_leading(acc, line, leading) |> commit_trailing(line, trailing)
    // standalone partial
    PartialTag(line, name), ClearsBoth ->
      append(acc, Partial(line, name, leading))
    // all other partial cases
    PartialTag(line, name), _ ->
      commit_leading(acc, line, leading)
      |> append(Partial(line, name, None))
      |> commit_trailing(line, trailing)
    // standalone section start
    SectionStartTag(line, name), ClearsBoth ->
      append(acc, SectionStart(line, name))
    // all other section start cases
    SectionStartTag(line, name), _ ->
      commit_leading(acc, line, leading)
      |> append(SectionStart(line, name))
      |> commit_trailing(line, trailing)
    // standalone inverted section start
    InvertedSectionStartTag(line, name), ClearsBoth ->
      append(acc, InvertedSectionStart(line, name))
    // all other section start cases
    InvertedSectionStartTag(line, name), _ ->
      commit_leading(acc, line, leading)
      |> append(InvertedSectionStart(line, name))
      |> commit_trailing(line, trailing)
    // blocks
    BlockStartTag(line, name), _ ->
      append(acc, BlockStart(line, name, clearance, leading, trailing))
    // parents
    ParentStartTag(line, name), _ ->
      append(acc, ParentStart(line, name, clearance, leading, trailing))
    // end tags
    EndTag(line, name), _ ->
      append(acc, End(line, name, clearance, leading, trailing))
  }
}

fn end_line(
  acc: Tree,
  state: State,
  line: Int,
  newline: Option(String),
) -> Tree {
  case state {
    // empty line with possibly whitespace
    LineStart(leading) ->
      case newline {
        // eof-terminated line, so we just write the whitespace
        None -> append_whitespace(acc, line, leading)
        // nl-terminated line, so we can prepend indentation marker, etc.
        Some(newline) ->
          append(acc, Indent(line))
          |> commit_leading(line, leading)
          |> append(Literal(line, newline))
      }
    // if the first tag was pending to be committed, then that means that
    // the line is empty, aside from the pending tag, so the tag clears both,
    // and there's no need to write the current line into the main accumulator
    TagPending(FirstTag(leading, tag, trailing)) ->
      commit_tag(acc, leading, tag, glom(trailing, newline), ClearsBoth)
    // if the latest tag was pending to be committed, then that means that the
    // line is NOT empty, so the tag only clears the end (and this is then a
    // content line), and we absorb the trailing whitespace into the element
    TagPending(InlineTag(current_line, tag, trailing)) ->
      append(acc, Indent(line))
      |> append_tree(current_line)
      |> commit_tag(None, tag, glom(trailing, newline), ClearsEnd)
    // content
    Content(current_line, literal) ->
      append(acc, Indent(line))
      |> append_tree(current_line)
      |> append_literal(line, glom(literal, newline))
  }
}

fn commit_leading(acc: Tree, line: Int, leading: Option(String)) -> Tree {
  case leading {
    Some(leading) -> append(acc, Leading(line, leading))
    None -> acc
  }
}

fn commit_trailing(acc: Tree, line: Int, trailing: Option(String)) -> Tree {
  case trailing {
    Some(trailing) -> append(acc, Literal(line, trailing))
    None -> acc
  }
}

fn glom(acc: Option(String), literal: Option(String)) -> Option(String) {
  case literal {
    None -> acc
    Some(literal) -> glom_literal(acc, literal)
  }
}

fn glom_literal(acc: Option(String), literal: String) -> Option(String) {
  case acc, literal {
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

fn append_whitespace(acc: Tree, line: Int, token: Option(String)) -> Tree {
  case token {
    Some(lexeme) -> append(acc, Literal(line, lexeme))
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
    End(_, path, _, _, _) -> token_name_with_path("END_TAG", path)
    Partial(_, name, _) ->
      token_name_with_path("PARTIAL", case name {
        scanner.StaticName(name) -> [name]
        scanner.DynamicName(path) -> path
      })
    RawVariable(_, path) -> token_name_with_path("RAW_VARIABLE", path)
    Variable(_, path) -> token_name_with_path("VARIABLE", path)
    Indent(_) -> "INDENT"
    Leading(_, _) -> "LEADING"
    Eof(_) -> "EOF"
  }
}

fn token_name_with_path(name: String, path: List(String)) -> String {
  name <> "(" <> string.join(path, ".") <> ")"
}
