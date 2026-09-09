//// Mustache syntactical grammar:
////
//// template        -> expression* ;
//// expression      -> TEXT | variable | raw_variable | section_opening | SET_DELIMITERS | IGNORED ;
//// variable        -> LEFT_DELIMITER name RIGHT_DELIMITER
//// raw_variable    -> (LEFT_DELIMITER "&" | "{{{") name ("}}}" | RIGHT_DELIMITER)
//// section         -> section_opening expression* closing_tag
//// section_opening -> LEFT_DELIMITER "#" name RIGHT_DELIMITER
//// sigil           -> "^" | ">" | "$" | "<"
//// closing_tag     -> LEFT_DELIMITER "/" name RIGHT_DELIMITER
//// name            -> IDENTIFIER* ("." IDENTIFIER*)*

