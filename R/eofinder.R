#' Convert eofinder item response to sf
#'
#' Internal helper thus not exported
#'
#' @param item A list object represening a single item response from eofinder
#'
#' @return An sf object
#' @keywords internal
#' @importFrom sf st_as_sfc st_as_sf
#' @importFrom tibble enframe
#' @importFrom dplyr filter mutate
#' @importFrom tidyr pivot_wider unnest everything
parse_item <- function(item){
  name <- NULL
  coords <-unlist(item$geometry$coordinates)
  id <- item$id
  longs <- coords[c(T, F)]
  lats <- coords[c(F,T)]
  coords <- paste(longs, lats, collapse = ",")
  geom <- paste0("Polygon((", coords, "))") |> st_as_sfc(crs = 4326)

  item$properties |>
    enframe() |>
    filter(!name %in% c("license", "keywords", "centroid", "services", "links")) |>
    pivot_wider() |>
    unnest(everything()) |>
    mutate(geom = geom,
           id = id) |>
    st_as_sf()
}


#' Collect the response of a query to eofinder
#'
#' Internal helper thus not exported
#'
#' @param query A charachter with the API query parameters
#'
#' @return An sf object
#' @keywords internal
#' @importFrom httr GET content
#' @importFrom purrr map list_rbind
#' @importFrom sf st_as_sf
#' @importFrom tibble as_tibble
collect_responses <- function(query){

  response <- GET(query)

  if (response$status_code != 200){
    stop(
      "Query failed with following message:\n",
      content(response)$ErrorMessage
    )
  }
  cnt <- content(response)
  n_items <- cnt$properties$totalResults
  items_pp<- cnt$properties$itemsPerPage
  n_pages <- ceiling(n_items / items_pp)

  if (n_items == 0) {
    stop("No results found for the specified search filters.")
  }

  # collect first page to avoid re-querying the server
  results <- map(cnt$features, parse_item) |>
    list_rbind() |>
    as_tibble() |>
    st_as_sf()

  if(n_pages > 1){
    other_pages <- map(2:n_pages, function(page){
      url <- paste0(query, "&page=", page)
      response <- GET(url)
      cnt <- content(response)
      items <- map(cnt$features, parse_item) |>
        list_rbind()
    }) |>
      list_rbind() |>
      as_tibble() |>
      st_as_sf()

    results <- do.call(rbind, list(results, other_pages))
  }
  results
}



#' Query Sentinel-2 scenes from eofinder
#'
#' Using the eofinder API, this function can be used to query
#' matching Sentinel-2 scenes with a user-defined spatio-temporal
#' extent. This functions returns an sf object with additional
#' meta data for each acqusition which can be used for further filtering
#' of the results.
#'
#' @param aoi An unprojected sf object. Its bounding box will be used to
#'   query th eofinder API.
#' @param level The processing level of the collection to query. Available
#'   values are "LEVEL1", "LEVEL2A", "LEVEL2AP", and "LEVEL3".
#' @param product The product to query. Available options are "L1C", "L2A",
#'   "L2A-MAJA", "L2A-FORCE", and "L3-WASP", depending on the selected level.
#' @param cloudcover A numeric giving the maximum allowed cloud cover.
#' @param start A character or date object indicating the start of the
#'   temporal window for the query.
#' @param end A character or date object indicating the end of the
#'   temporal window for the query.
#'
#' @return An sf object with one matching acquisition per row.
#' @export
#' @importFrom sf st_bbox st_as_sfc st_as_text st_intersection st_area st_geometry
#' @importFrom tibble tribble
#' @importFrom glue glue
#' @importFrom utils URLencode
query_s2_codede <- function(
    aoi = NULL,
    level = NULL,
    product = NULL,
    cloudcover = 100,
    start = "2015-01-01 00:00:00 CET",
    end = Sys.time()){

  if (is.null(aoi) | !inherits(aoi, "sf")){
    stop("aoi must be an sf object")
  }

  geometry <- st_bbox(aoi) |> st_as_sfc() |> st_as_text() |> URLencode()


  s2_collections <- tribble(
    ~ collection, ~ levels, ~ type,
    "Sentinel2", "LEVEL1", "L1C",
    "Sentinel2", "LEVEL2A", c("L2A", "L2A-MAJA", "L2A-FORCE"),
    "Sentinel2", "LEVEL2AP", "L2A",
    "Sentinel2", "LEVEL3",  "L3-WASP"
  )

  if(is.null(level) | !level %in% s2_collections$levels){
    stop(paste0(
      "Level must be one of:\n",
      paste(s2_collections$levels, collapse= "\n")
    )
    )
  }

  if(!product %in% unlist(s2_collections$type[s2_collections$levels == level])){
    stop(
      paste0("Available products for level '", level,"':\n",
             paste(s2_collections$type[s2_collections$levels == level], collapse ="\n")
      )
    )
  }

  if (!inherits(cloudcover, "numeric") | cloudcover < 0 | cloudcover > 100){
    stop("cloudcover must be a numeric between 0 and 100.")
  }
  cloudcover <- paste0("[0,", cloudcover, "]")

  date_format <- "%Y-%m-%dT%H:%M:%SZ"
  start <- try(
    format(as.Date(start), date_format),
    silent = TRUE
  )

  if(inherits(start, "try-error")){
    stop(
      "Formatting start to datetime format '%Y-%m-%dT%H:%M:%SZ' resulted in the following error:\n",
      start
    )
  }

  end <- try(
    format(as.Date(end), date_format),
    silent = TRUE
  )

  if(inherits(end, "try-error")){
    stop(
      "Formatting end to datetime format '%Y-%m-%dT%H:%M:%SZ' resulted in the following error:\n",
      end
    )
  }

  query <- glue(
    "https://finder.code-de.org/resto/api/collections/Sentinel2/search.json?",
    "location=local&",
    "processingLevel={level}&",
    "productType={product}&",
    "cloudCover={cloudcover}&",
    "startDate={start}&",
    "completionDate={end}&",
    "geometry={geometry}"
  )

  # collect results
  collect_responses(query)
}


#' Download matched acquisitions from CODE-DE
#'
#' Use this function to download matching Sentinel-2 acquisitions from
#' the CODE-DE data storage to your local machine. This functions assumes that
#' specify an API key which requires you to have a subscription with CODE-DE.
#' Currently, the easiest way to obtain such an API key is to head over to
#' \url{https://finder.code-de.org/}, log-in with your user account, query some
#' spatio-temporal extent and copy the key from the URL results.
#'
#' @param s2_matches An sf object returned from calling `query_s2_codede()`.
#' @param key  A character vector indicating an CODE-DE API key.
#' @param outdir A character vector indicating the directory where the downloads
#'   should be written to.
#'
#' @return Nothing, called for its side effect.
#' @export
#' @importFrom glue glue
#' @importFrom purrr walk2
#' @importFrom utils download.file
#'
download_S2_codede <- function(
    s2_matches = NULL,
    key = NULL,
    outdir = "."
){

  if (is.null(key)){
    stop("Missing EOFinder API key. Please specify...")
  }

  if (!inherits(s2_matches, "sf")){
    stop("Expects `s2_matches` to be an sf object returned by `query_s2_codede()`.")
  }

  ids <- s2_matches$id

  urls <- glue(
    "https://zipper.prod.cloud.code-de.org/download/{ids}",
    "?token={key}"
  )

  filenames <- file.path(outdir, paste0(basename(s2_matches$productIdentifier), ".zip"))

  walk2(urls, filenames, function(url, file){
    download.file(url, destfile = file)
  })
}





