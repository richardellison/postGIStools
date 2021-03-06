#' Send SELECT query and parse geometry, hstore columns
#'
#' This function is an extension of \code{\link[DBI]{dbGetQuery}} that is useful
#' in cases where selected columns include a PostgreSQL hstore, which is parsed
#' as a list-column, and/or a PostGIS geometry, in which case the output is a
#' spatial data frame (from the \code{\link[sp]{sp}} package).
#'
#' Conversion to spatial data frame objects will fail if there are \code{NULL}
#' values in the geometry column, so these should be filtered out in the provided
#' query statement.
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
#'
#' @examples
#' \dontrun{
#' library(RPostgreSQL)
#' con <- dbConnect(PostgreSQL(), dbname = "my_db")
#'
#' # If geom column holds points, returns a SpatialPointsDataFrame
#' cities <- get_postgis_query(con, "SELECT name, geom, datalist FROM city",
#'                             geom_name = "geom", hstore_name = "datalist")
#'
#' # Get the populations (part of datalist hstore) as a vector
#' pop <- cities@data$datalist %->% "population"
#' }
#'
#' @references The code for importing geom fields is based on a blog post by
#'   Lee Hachadoorian: \href{http://www.r-bloggers.com/load-postgis-geometries-in-r-without-rgdal/}{Load PostGIS geometries in R without rgdal}.
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
    if (length(statement) != 1 | !grepl("^select", tolower(statement))) {
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

    # Convert geom field to WKT text format
    #  and join with spatial_ref_sys for projection information
    if (!is.na(geom_name)) {
        geom_select <- paste0("ST_AsText(", quote_id(geom_name), ") AS ",
                              quote_id(paste0(geom_name, "_wkt")), ", ",
                              "ST_SRID(", quote_id(geom_name), ") AS ",
                              quote_id(paste0(geom_name, "_srid")))
        geom_join <- paste0("LEFT JOIN spatial_ref_sys ON ",
                            "ST_SRID(", quote_id(geom_name), ")", " = srid")
    } else {
        geom_select <- ""
        geom_join <- ""
    }

    # Convert hstore field to JSON
    if (!is.na(hstore_name)) {
        hstore_select <- paste0("hstore_to_json(", quote_id(hstore_name),
                                ") AS ", quote_id(paste0(hstore_name, "_json")))
    } else {
        hstore_select <- ""
    }

    # Add transformed fields to base query
    new_query <- paste0(
        "SELECT *",
        ifelse(is.na(geom_name), "", paste0(",", geom_select)),
        ifelse(is.na(hstore_name), "", paste0(",", hstore_select)),
        " FROM (", statement, ") baseqry",
        ifelse(is.na(geom_name), "", paste0(" ", geom_join)),
        ";"
    )

    new_query
}


process_select_result <- function(res, geom_name, hstore_name) {
    # Convert hstore (now JSON) column into list of lists
    if (!is.na(hstore_name)) {
        hs <- paste0(hstore_name, "_json")
        res[is.na(res[[hs]]), hs] <- "{}" # Replace SQL NULLs with empty lists
        res[[hstore_name]] <- lapply(as.character(res[[hs]]), jsonlite::fromJSON)
        res[[hs]] <- NULL
    }

    # If it has geom, convert into Spatial*DataFrame
    if (!is.na(geom_name)) {
        if (length(unique(res$proj4text)) > 1)
            stop("Returned geometries do not share the same projection.")
        proj <- unique(res$proj4text)
        geom_wkt <- paste0(geom_name, "_wkt")

        # Check spatial datatype
        sp_obj <- rgeos::readWKT(text = res[1, geom_wkt])
        # Spatial columns to be discarded
        sp_cols <- c(geom_wkt, geom_name, paste0(geom_name, "_srid"), "srid",
                     "auth_name", "auth_srid", "srtext", "proj4text")
        dat <- res[!(names(res) %in% sp_cols)]
        if (is(sp_obj, "SpatialPoints")) {
            res <- SpatialPointsDataFrame(
                coords = matrix(as.numeric(as.character(unlist(
                        strsplit(gsub("POINT\\(|)", "",res[, geom_wkt]), " ")
                    ))), ncol=2, byrow=TRUE),
                data = dat,
                proj4string = CRS(proj)
            )
        } else if (is(sp_obj, "SpatialLines")) {
            res <- SpatialLinesDataFrame(
                SpatialLines(
                    lapply(1:nrow(res), function(i) {
                        (rgeos::readWKT(res[i, geom_wkt], id = i))@lines[[1]]
                    }), proj4string = CRS(proj)
                ), dat
            )
        } else if (is(sp_obj, "SpatialPolygons")) {
            res <- SpatialPolygonsDataFrame(
                SpatialPolygons(
                    lapply(1:nrow(res), function(i) {
                        (rgeos::readWKT(res[i, geom_wkt],id = i))@polygons[[1]]
                    }), proj4string = CRS(proj)
                ), dat
            )
        } else {
            stop("geom. field cannot be mapped to Point, Line or Polygon type.")
        }
    }
    res
}
