//// Mustache syntactical grammar:
////
//// template                 -> expression* ;
//// expression               -> TEXT | section | inverted_section | partial | block | parent | variable | raw_variable;
//// section                  -> section_opening expression* closing_tag
//// section_opening          -> LEFT_DELIMITER "#" name RIGHT_DELIMITER
//// inverted_section         -> inverted_section_opening expression* closing_tag
//// inverted_section_opening -> LEFT_DELIMITER "^" name RIGHT_DELIMITER
//// partial                  -> LEFT_DELIMITER ">" expression* closing_tag
//// block                    -> block_opening expression* closing_tag
//// block_opening            -> LEFT_DELIMITER "$" name RIGHT_DELIMITER
//// parent                   -> parent_opening expression* closing_tag
//// parent_opening           -> LEFT_DELIMITER "<" name RIGHT_DELIMITER
//// closing_tag              -> LEFT_DELIMITER "/" name RIGHT_DELIMITER
//// raw_variable             -> (LEFT_DELIMITER "&" | "{{{") name ("}}}" | RIGHT_DELIMITER)
//// variable                 -> LEFT_DELIMITER name RIGHT_DELIMITER
//// name                     -> IDENTIFIER* ("." IDENTIFIER*)*

