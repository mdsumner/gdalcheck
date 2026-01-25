
av <- tools::CRAN_package_db()
ds <- grep("GDAL", av$Description, ignore.case = T)
sr <- grep("GDAL", av$SystemRequirements, ignore.case = T)
tt <- grep("GDAL", av$Title, ignore.case = TRUE)
ix <- sort(unique(c(ds, sr, tt)))

candidates <- c("terra", "sf", "gdalraster", "vapour", "gdalcubes", "stars", "raster")

has_contender <- function(x, pkgs) {
  pattern <- paste0(pkgs, collapse = "|")

  sapply(strsplit(x, ","), function(deps) any(stringr::str_detect(deps, pattern)))
}

via_imports  <- has_contender(av$Imports[ix], candidates)
via_suggests <- has_contender(av$Suggests[ix], candidates)
via_depends  <- has_contender(av$Depends[ix], candidates)
via_linksto  <- has_contender(av$LinkingTo[ix], candidates)

uses_known <- via_imports | via_suggests | via_depends | via_linksto

## packages that mention GDAL but don't use known bindings
(direct_candidates <- setdiff(sort(unique(na.omit(av$Package[ix][!uses_known]))), candidates))

#sapply(direct_candidates, \(.x) browseURL(sprintf("https://CRAN.R-project.org/package=%s", .x)))

# for (i in seq_len(nrow(av))) {
#   #system(sprintf("git clone %s", gsub("/issues", "", av$BugReports[i])));
#   p <- remotes::dev_package_deps(av[["Package"]][i], dependencies = TRUE)[["package"]]
# print(length(unique(p)))
#   pdeps <- c(pdeps, p)
#   };
#

