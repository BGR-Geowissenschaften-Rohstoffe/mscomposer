#' Multi-Spectral Image Composite Generation
#'
#' Composing an Analysis-Ready-Dataset based on spatially and temporally
#' diverse tiles over a large Area-of-Interest (AOI) can be a cumbersome process.
#' Using the gdalcubes package, it is almost trivial to calculate a harmonized
#' dataset over a given AOI. This function allows you to supply a number of
#' multi-spectral images and it will output a harmonized coverage of the spatial extent.
#' Choose the dx, dy, and srs arguments to get the results in your preferred
#' CRS and spatial resolution. Choose dt close to the temporal sampling over your
#' AOI, e.g. 12 days. Based on the chosen reducer, the temporal dimension will
#' be reduced before the output is created. If you wish to obtain results for
#' different time periods, divide your input files accordingly and call the
#' function multiple times.
#'
#' @param files A character vector with the file paths to the individual
#'   images band files.
#' @param format A character vector of the format to use or file to a `.json`
#'   file with a default format (see \code{gdalcubes::collection_formats()})
#' @param view A cube view object either created using mscompose::view() ord gdalcubes::cube_view().
#' @param col A path to an image collection created during a previous call of this function
#'   or a path where the collection should be written to.
#' @param mask A mask object created with \code{gdalcubes::image_mask()}.
#' @param bands A character vector of the bands you wish to retain in the output.
#'  Note, that all bands needed for the indices calculation also need to be appear
#'  here.
#' @param reducers A character vector for the method used for the final reduction
#'  of the temporal dimension (see \code{gdalcubes::reduce_time.cube()})
#' @param indices A named list containing the band specific formula
#'  for one or more spectral indices to add to the cube (see \code{gdalcubes::apply_pixel.cube()}).
#' @param filters A named list containing band/index specific conditions, which only
#'   retain those pixels where the conditions evaluate to TRUE (see \code{gdalcubes::filter_pixel()}).
#' @param outdir A path to a directory where the output file will be written to.
#' @param prefix A character used as a pre-fix for the output file.
#' @param ... Additional arguments for \code{gdalcubes::write_tif()}
#'
#' @return Nothing, called for its side-effect to write a file to disk
#' @export
#' @examples
#' # load required libraries
#' if (FALSE){
#' library(sf)
#' library(gdalcubes)
#' library(mscomposer)
#'
#' # parameter definitions
#' s2_files <- list.files(
#'               system.file("extdata/Sentinel2/", package="mscomposer"),
#'               pattern = ".jp2$", full.names = TRUE, recursive = TRUE)
#' format <- system.file("Sentinel2_L2A_flat.json", package = "mscomposer")
#' indices <- list(NDVI = "(B08-B04)/(B08+B04)")
#' filters <- list(NDVI = "NDVI < 0.2")
#' aoi <- st_read(system.file("aoi_S2.gpkg", package="mscomposer"))
#' cv <- ms_view(
#'   aoi = aoi,
#'   srs = "utm",
#'   dt = "P14D",
#'   dx = 10,
#'   dy = 10,
#'   start = "2018-01-01T00:00:00",
#'   end = "2018-12-31T23:59:59",
#'   agg = "median",
#'   rsmp = "bilinear")
#' mask = image_mask("SCL", values = c(1,3,6,8,9,10,11))
#' bands = c("B02", "B03", "B04","B08")
#' reducer = "median"
#' outdir = tempdir()
#' prefix = "median-composite-"
#'
#' # function call
#' ms_compose(
#'   s2_files,
#'   format,
#'   view=cv,
#'   col = file.path(tempdir(), "S2.sqlite"),
#'   mask=mask,
#'   bands=bands,
#'   reducers=reducer,
#'   indices=indices,
#'   filters=filters,
#'   outdir=outdir,
#'   prefix=prefix
#'  )
#'}
ms_compose <- function(
    files=NULL,
    format="Sentinel2_L2A",
    view=NULL,
    col=tempfile(fileext = ".sqlite"),
    mask=NULL,
    bands=NULL,
    reducers=NULL,
    indices=NULL,
    filters=NULL,
    outdir=NULL,
    prefix="composite-",
    ...
){

  # make assertions
  if (!requireNamespace("sf", quietly = TRUE)){
    stop("sf is required. Install with 'install.packages('sf')'")
  }

  if (!requireNamespace("gdalcubes", quietly = TRUE)){
    stop("gdalcubes is required. Install with 'install.packages('gdalcubes')'")
  }

  if(!inherits(view, "cube_view")){
    stop("view needs to be of class cube_view.")
  }

  if (!is.null(indices)){
    if(any(!inherits(indices, "list"),
           is.null(names(indices)))){
      stop(paste(
        "indices and filters must both be named lists, e.g.:\n",
        "indices <- list(NDVI = '(B08-B04)/(B08+B04)')")
      )
    }
  }

  if (!is.null(filters)){
    if(any(!inherits(filters, "list"),
           is.null(names(filters)))){
      stop(paste(
        "indices and filters must both be named lists, e.g.:\n",
        "filters <- list(NDVI = 'NDVI < 0.2')")
      )
    }
  }

  if (!is.null(mask)){
    if (!inherits(mask, "image_mask")){
      stop("mask must be create with gdalcubes::image_mask()")
    }
  }

  if(!dir.exists(outdir)){
    dir.create(outdir)
  }


  # existing or new image collection?
  if (file.exists(col)){
    coll <- image_collection(col)
  } else {
    coll <- create_image_collection(
      files,
      format = format,
      out_file = col
    )
  }
  # TODO: check that mask and indices bands are present
  # currently, R crashes when calling bands()

  # if(!mask$band %in% bands(coll)){
  #   stop("Mask band not found in image collection.")
  # }

  # create cube, potentially calculate indices and apply filters
  cube <- raster_cube(coll, view, mask) |>
    select_bands(bands) |>
    {\(x) if(!is.null(indices)) apply_pixel(x, unlist(indices), names = names(indices), keep_bands = TRUE) else x }() |>
    {\(x) if(!is.null(filters)) filter_pixel(x, unlist(filters)) else x }()

  # reduce temporal dimension to create the composite
  if (!is.null(reducers)){
    if (!is.null(indices)){
      bands <- c(bands, names(indices))
    }
    reduction_terms <- unlist(lapply(reducers, function(x) paste0(x, "(", bands, ")")))

    cube <- cube |>
      reduce_time(reduction_terms)
  }

  # write output GTiff
  cube |>
    write_tif(dir = outdir, prefix = prefix, ...)

}



