[![Travis-CI Build Status](https://travis-ci.org/SESYNC-ci/postGIStools.svg?branch=master)](https://travis-ci.org/SESYNC-ci/postGIStools)

## Purpose ##

This package simplifies the R interface to PostgreSQL databases containing geometries and associated hstore fields.

##List of functions##

- `%->%`: An operator that mimics the `[hstore] -> [key]` operator in PostgreSQL. For example, if *hs* is a hstore-column in data.frame *df*, `df$hs %->% "a_key"` pulls a vector containing the values associated with key *a_key* from each row. It can also be used with assignments, e.g.: `df$hs[3] %->% "a_key" <- "new_value"`. 

- `get_postgis_query`: A wrapper around `dbGetQuery` that automatically parses geometry and hstore columns. The latter is converted into a list of lists in R, i.e. each cell contains a named list of key-value pairs. If the query includes a geometry field, it returns a R spatial object (i.e. *Spatial[Points/Lines/Polygons]DataFrame*); otherwise, a simple data frame.

- `new_hstore`: Creates an empty list of lists with a specific number of records. It primarily serves to create a hstore column from scratch in a data frame, that can be then inserted into PostgreSQL.

- `postgis_insert`: Builds a query to insert rows from a specified data frame into a database table, after re-transforming (if applicable) the geometry and hstore information in PostgreSQL format.

- `postgis_update`: Builds a query to update certain rows in a database table based on the information in a data frame. If applicable, the geometry and hstore information is appropriately transformed, and the hstore column is updated by concatenation (i.e. as with the `||` operator in PostgreSQL).


## How to install ##

Install the package from this GitHub repository using the following code:
```R
install.packages("devtools")  # if necessary
devtools::install_github("SESYNC-ci/postGIStools")
```

## References ##

The code to import geom fields is based on blog post from Lee Hachadoorian:
[Load PostGIS geometries in R without rgdal](http://www.r-bloggers.com/load-postgis-geometries-in-r-without-rgdal/)

## Acknowledgements ##

Development of this R package was supported by the National Socio-Environmental Synthesis Center (SESYNC) under funding received from the National Science Foundation DBI-1052875.
