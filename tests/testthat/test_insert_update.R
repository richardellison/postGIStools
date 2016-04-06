library(postGIStools)
context("postgis_insert and update")

# Connect to test database
con <- RPostgreSQL::dbConnect(RPostgreSQL::PostgreSQL(),
                              dbname = "d2u06to89nuqei", user = "mzcwtmyzmgalae",
                              host = "ec2-107-22-246-250.compute-1.amazonaws.com",
                              password = "UTv2BuwJUPuruhDqJthcngyyvO")

# Read in info for 10 countries (saved in file)
country_sp <- readRDS("country_sp.rds")

# Create new temporary table in DB
RPostgreSQL::dbSendQuery(con, paste("CREATE TEMP TABLE cty_tmp (name text,",
                                    "iso2 text PRIMARY KEY, capital text,",
                     "population integer, translations hstore, geom geometry)"))


# Insert first two rows and re-import
postgis_insert(con, country_sp[1:2, ], "cty_tmp",
               geom_name = "geom", hstore_name = "translations")
qry <- get_postgis_query(con, paste("SELECT name, iso2, capital, population,",
                                    "translations, geom FROM cty_tmp"),
                         geom_name = "geom", hstore_name = "translations")
qry <- qry[order(match(qry$iso2, country_sp$iso2)), ]

test_that("postgis_insert correctly inserts full rows", {
    expect_equal(country_sp[1:2, -5], qry[, -5])
    expect_equal(country_sp$translations[1:2] %->% "it",
                 qry$translations %->% "it")
})


# Insert partial information for a few rows
postgis_insert(con, country_sp[3, ], "cty_tmp", write_cols = c("name", "iso2"),
               geom_name = "geom")
postgis_insert(con, country_sp[4, ], "cty_tmp",
               write_cols = c("name", "iso2", "translations"),
               geom_name = "geom", hstore_name = "translations")
qry <- get_postgis_query(con, paste("SELECT name, iso2, capital, population,",
                                    "translations, geom FROM cty_tmp"),
                         geom_name = "geom", hstore_name = "translations")
qry <- qry[order(match(qry$iso2, country_sp$iso2)), ]

test_that("postgis_insert correctly inserts partial rows", {
    expect_equal(country_sp@polygons[1:4], qry@polygons)
    expect_equal(country_sp$translations[c(1, 2, 4)] %->% "es",
                 qry$translations[c(1, 2, 4)] %->% "es")
})


test_that("postgis_insert fails on bad inputs", {
    # No geom_name for spatial and vice versa
    expect_error(postgis_insert(con, country_sp[9:10, ], "cty_tmp"))
    expect_error(postgis_insert(con, country_sp@data[9:10, ], "cty_tmp",
                                geom_name = "geom"))
})


RPostgreSQL::dbSendQuery(con, "DROP TABLE cty_tmp")
RPostgreSQL::dbDisconnect(con)
