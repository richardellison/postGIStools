library(postGIStools)
context("get_postgis_query")

# Connect to test database
con <- tryCatch(RPostgreSQL::dbConnect(RPostgreSQL::PostgreSQL(),
                             dbname = "d2u06to89nuqei", user = "mzcwtmyzmgalae",
                             host = "ec2-107-22-246-250.compute-1.amazonaws.com",
                             password = "UTv2BuwJUPuruhDqJthcngyyvO"),
                error = function(e) NULL)

# Projection used in data
proj_wgs84 <- "+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"

test_that("get_postgis_query works for simple queries", {
    if (is.null(con)) skip("PostgreSQL connection unavailable")
    qry <- get_postgis_query(con,
        "select name, capital, population from country where iso2 = 'CA'")
    resp <- data.frame(name = "Canada", capital = "Ottawa",
                       population = 35749600, stringsAsFactors = FALSE)
    expect_equal(qry, resp)
})


test_that("get_postgis_query correctly imports hstore", {
    if (is.null(con)) skip("PostgreSQL connection unavailable")
    qry <- get_postgis_query(con,
        "SELECT name, translations FROM country WHERE iso2 = 'BR'",
        hstore_name = "translations")
    # Check that importing just hstore works
    qry2 <- get_postgis_query(con,
        "SELECT translations FROM country WHERE iso2 = 'BR'",
        hstore_name = "translations")
    expect_equal(qry$translations %->% "es", "Brasil")
    expect_equal(qry$translations, qry2$translations)
})


test_that("get_postgis_query correctly imports geometry", {
    if (is.null(con)) skip("PostgreSQL connection unavailable")
    qry <- get_postgis_query(con,
        "SELECT name, geom FROM country WHERE iso2 IN ('KE', 'TZ')",
        geom_name = "geom")
    qry2 <- get_postgis_query(con,
        "SELECT geom FROM country WHERE iso2 IN ('KE', 'TZ')",
        geom_name = "geom")
    pts <- SpatialPoints(cbind(c(35.7, 36.8), c(-6.2, -1.3)),
                               proj4string = CRS(proj4string(qry)))
    # Check projection and overlay with known points
    expect_equal(proj4string(qry), proj_wgs84)
    expect_equal(over(pts, qry)$name, c("Tanzania", "Kenya"))
    # Importing just geometry should result in zero-column @data
    expect_length(qry2@polygons, 2)
    expect_equal(dim(qry2@data), c(2, 0))
})


test_that("get_postgis_query works with SELECT * (wildcard)", {
    if (is.null(con)) skip("PostgreSQL connection unavailable")
    qry <- get_postgis_query(con,
                             "SELECT * FROM country WHERE iso2 IN ('KE', 'TZ')",
                             geom_name = "geom", hstore_name = "translations")
    pts <- SpatialPoints(cbind(c(35.7, 36.8), c(-6.2, -1.3)),
                         proj4string = CRS(proj4string(qry)))
    # Check overlay with known points
    expect_equal(over(pts, qry)$name, c("Tanzania", "Kenya"))
    # Check hstore data
    expect_equal(qry$translations[1] %->% "es", "Kenia")
})


test_that("get_postgis_query correctly imports points from ST_Centroid", {
    if (is.null(con)) skip("PostgreSQL connection unavailable")
    qry <- get_postgis_query(con,
        "SELECT ST_Centroid(geom) centr FROM country WHERE iso2 IN ('KE', 'TZ')",
        geom_name = "centr")
    # Verify class and x coord. of first point (within 0.001)
    expect_is(qry, "SpatialPointsDataFrame")
    expect_lt(abs(qry@coords[1, 1] - 37.8247), 0.001)
})


test_that("get_postgis_query correctly imports lines from ST_Boundary", {
    if (is.null(con)) skip("PostgreSQL connection unavailable")
    qry <- get_postgis_query(con,
        "SELECT ST_Boundary(geom) bound FROM country WHERE iso2 IN ('KE', 'TZ')",
        geom_name = "bound")
    # Verify class and number of lines
    expect_is(qry, "SpatialLinesDataFrame")
    expect_length(qry@lines[[1]]@Lines, 2)
    expect_length(qry@lines[[2]]@Lines, 4)
})


test_that("get_postgis_query fails on bad inputs", {
    if (is.null(con)) skip("PostgreSQL connection unavailable")
    expect_error(get_postgis_query(0, "SELECT * FROM country"))
    expect_error(get_postgis_query(con, "CREATE TABLE tab_tmp (test text)"))
    expect_error(get_postgis_query(con, "SELECT * FROM country", geom_name = 0))
})


if (!is.null(con)) RPostgreSQL::dbDisconnect(con)
