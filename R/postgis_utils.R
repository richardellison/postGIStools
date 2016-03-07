### Utility functions used by package (not exported)

# Convert JSON string representation to hstore
json_to_hstore <- function(str) {
    stringr::str_replace_all(str, c("\\{" = "", "\\}" = "", "\\[" = "",
                                    "\\]" = "", "\\:" = "=>", "," = ", "))
}

# Make shortcut functions to quote identifiers and strings from given connection
make_id_quote <- function(conn) {
    function(s) DBI::dbQuoteIdentifier(conn, s)
}
make_str_quote <- function(conn) {
    function(s) DBI::dbQuoteString(conn, s)
}

# Shortcut to test if argument is a single character string
test_single_str <- function(s) {
    if (!is.character(s) | length(s) != 1) {
        stop(paste(deparse(substitute(s)), "is not a single character string"))
    }
}
