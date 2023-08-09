#' Create a view from an sf object
#'
#' Helper function to create a cube view based on the bounding box of a user supplied
#' aoi sf-object. Youn can either choose to automatically derive a
#' \href{https://proj.org/operations/projections/laea.html}{Lambert Azimuthal Equal Area  (LAEA)}
#' or a \href{https://proj.org/operations/projections/utm.html}{Universal Transverse Mercator (UTM)}
#' projection for their study area. Both will use the WGS84 ellipsoid. You can
#' also chose to supply a valid crs object. In this case the supplied CRS will be
#' used as-is. You also need to supply the spatial and temporal resolution for your
#' view as well as the start and end date-time for your analysis. See \code{gdalcubes::cube_view()}
#' for more information
#'
#' @param aoi An sf object from which the spatial extent for the view is derived.
#' @param srs Either a character vector with 'laea' or 'utm' for automatic
#'   construction of a CRS, or a valid CRS object created with \code{sf::st_crs()}
#' @param dt A character vector determining the temporal resolution of the view.
#' @param dx A numeric vector determining the spatial resolution in x direction.
#' @param dy A numeric vector determining the spatial resolution in y direction.
#' @param start A character vector determining the start date-time of the view.
#' @param end A character vector determining the end date-time of the view.
#' @param agg A character vector determining the method used to aggregate pixels
#'  that fall into the same time-step.
#' @param rsmp A character vector determining the method used to resample pixels
#'  to the new spatial extent.
#'
#' @return A cube_view object.
#' @export
#'
#' @examples
#' library(sf)
#' (view <- system.file("aoi_S2.gpkg", package="mscomposer")) |>
#'   st_read(quiet = TRUE) |>
#'   ms_view(
#'     srs="utm",
#'     dt = "P1M",
#'     dx = 10,
#'     dy = 10,
#'     start = "2018-01-01T00:00:00",
#'     end = "2018-12-31T23:59:59",
#'     agg = "median",
#'     rsmp = "bilinear")
ms_view <- function(
    aoi=NULL,
    srs="laea",
    dt,
    dx,
    dy,
    start=NULL,
    end=NULL,
    agg="median",
    rsmp="bilinear"
){


  if (any(missing(dt),
          missing(dx),
          missing(dy))){
    stop("Please specify dt, dx, and dy to describe the spatio-temporal extent.")
  }

  if (any(is.null(start),
          is.null(end))){
    stop(paste(
      "Start and end time need to be specified like:\n",
      "start = '2018-01-01T00:00:00'\n",
      "end = '2018-12-31T23:59:59'"
    ))
  }

  # We are only interested in the bounding box
  aoi <- aoi |>
    st_bbox() |>
    st_as_sfc()

  if (inherits(srs, "crs")){ # if user supplied a CRS object
    proj <- srs
  } else { # if user supplied either auto laea or utm

    if (!srs %in% c("laea", "utm")){
      stop("srs must be one of 'laea' or 'utm' or a CRS object.")
    }

    if(!st_is_longlat(aoi)){ # need Lon/Lat for auto creation of proj
      warning(paste(
        "AOI was not supplied in geodetic coordinates.\n",
        "Trying to transform...")
      )
      aoi <- st_transform(aoi, 4326)
    }

    # get rounded coordinates of centorid
    coords <- aoi |>
      st_centroid() |>
      st_coordinates() |>
      round(4)

    if (srs == "laea"){ # laea creation
      proj <- st_crs(
        sprintf("+proj=laea +lon_0=%s +lat_0=%s +ellps=WGS84",
                coords[1],
                coords[2])
      )
    } else { # utm creation
      zone <- floor((coords[1] + 180) / 6) + 1
      hemisphere <- ifelse(coords[2] > 0, "", " +south")
      proj <- st_crs(
        sprintf("+proj=utm +zone=%s +ellps=WGS84%s",
                zone, hemisphere)
      )
    }
  }

  # get bounding box for the extent
  bbox <- aoi |>
    st_transform(proj) |>
    st_bbox() |>
    as.numeric()

  # create extent list
  extent <- list(
    left = bbox[1],
    right = bbox[3],
    bottom = bbox[2],
    top = bbox[4],
    t0 = start,
    t1 = end
  )

  # create the view
  view <- cube_view(
    extent=extent,
    srs=proj$wkt,
    dx=dx,
    dy=dy,
    dt=dt,
    aggregation = agg,
    resampling = rsmp
  )

  # return
  view
}
