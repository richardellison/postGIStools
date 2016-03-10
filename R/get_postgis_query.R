#' Send SELECT query and parse geometry, hstore columns
#'
#' This function can be used instead of \code{\link[DBI]{dbGetQuery}} when the
#' selected columns include a PostgreSQL hstore, which is parsed as a list-column,
#' and/or a PostGIS geometry, in which case the output is a spatial data frame
#' (from the \code{\link[sp]{sp}} package).
#'
#' @param conn A \code{\link[RPostgreSQL]{PostgreSQLConnection-class}} object,
#'   such as the output of \code{\link[DBI]{dbConnect}}.
#' @param statement Character string for a SQL SELECT query.
#' @param geom_name Name of the geometry column (\code{NA} if none).
#' @param hstore_name Name of the hstore column (\code{NA} if none).
#' @return Either a data frame (if \code{geom_name = NA}) or a
#'   Spatial[Points/Lines/Polygons]DataFrame containing the query result. If a
#'   hstore column is present, it appears as a list-column in the data frame,
#'   i.e. each cell is a named list of key-value pairs.
#' @seealso The \code{\link{\%->\%}} operator for working with hstore columns;
#'   \code{\link{postgis_insert}} and \code{\link{postgis_update}} for writing
#'   to a PostgreSQL connection.
#' @export
get_postgis_query <- function(conn, statement, geom_name = NA_character_,
                              hstore_name = NA_character_) {
    # Check inputs
    if (!is(conn, "PostgreSQLConnection")) {
        stop("conn is not a valid PostgreSQL connection")
    }
    if (length(statement) != 1 | !grepl("SELECT", statement)) {
        stop("statement does not appear to be a SELECT query")
    }
    test_single_str(geom_name)
    test_single_str(hstore_name)

    new_query <- edit_select_query(conn, statement, geom_name, hstore_name)

    # Get query output (suppress warnings that json is unrecognized)
    res <- suppressWarnings(RPostgreSQL::dbGetQuery(conn, new_query))

    process_select_result(res, geom_name, hstore_name)
}


## Non-exported functions called by get_postgis_query

edit_select_query <- function(conn, statement, geom_name, hstore_name) {
    # Make shortcut functions for SQL quoting
    quote_id <- make_id_quote(conn)

    # Add conversion of geom field to WKT text format
    new_query <- statement
    if (!is.na(geom_name)) {
        if (!grepl(geom_name, new_query, fixed = TRUE)) {
            warning(paste("geom. field", geom_name,
                          "absent from query statement."))
            geom_name <- NA
        } else {
            geom_sub <- paste0("ST_AsText(", quote_id(geom_name), ") AS ",
                               quote_id(paste0(geom_name, "_wkt")))
            new_query <- gsub(geom_name, geom_sub, new_query, fixed = TRUE)
        }
    }

    # Add conversion of hstore field to JSON
    if (!is.na(hstore_name)) {
        if (!grepl(hstore_name, new_query, fixed = TRUE)) {
            warning(paste("hstore field", hstore_name,
                          "absent from query statement."))
            hstore_name <- NA
        } else {
            hstore_sub <- paste0("hstore_to_json(", quote_id(hstore_name),
                                 ") AS ", quote_id(paste0(hstore_name, "_json")))
            new_query <- gsub(hstore_name, hstore_sub, new_query, fixed = TRUE)
        }
    }

    new_query
}


process_select_result <- function(res, geom_name, hstore_name) {
    # Convert hstore (now JSON) column into list of lists
    if (!is.na(hstore_name)) {
        hs <- paste0(hstore_name, "_json")
        res[[hstore_name]] <- lapply(as.character(res[[hs]]), jsonlite::fromJSON)
        res[[hs]] <- NULL
    }

    # If it has geom, convert into Spatial*DataFrame
    if (!is.na(geom_name)) {
        geom_wkt <- paste0(geom_name, "_wkt")
        sp_obj <- do.call(rbind, Map(rgeos::readWKT, text = res[[geom_wkt]],
                                     id = 1:nrow(res)))
        dat <- res[names(res) != geom_wkt]
        if (is(sp_obj, "SpatialPoints")) {
            res <- SpatialPointsDataFrame(sp_obj, dat)
        } else if (is(sp_obj, "SpatialLines")) {
            res <- SpatialLinesDataFrame(sp_obj, dat)
        } else if (is(sp_obj, "SpatialPolygons")) {
            res <- SpatialPolygonsDataFrame(sp_obj, dat)
        } else {
            stop("geom. field cannot be mapped to Point, Line or Polygon type.")
        }
    }
    res
}
