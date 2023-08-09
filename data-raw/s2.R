library(sf)
library(terra)
library(purrr)
library(furrr)
library(future)
library(progressr)
plan(multisession, workers = 24)

path <- "/path/to/Sentinel2"
folders <- list.files(path, pattern = "SAFE", full.names = TRUE)
tiles <- grep("T32TNT|T32TMT", folders, value = TRUE)
s2_images <- list.files(tiles, pattern = ".jp2$", full.names = TRUE, recursive = TRUE)
s2_images <- grep("2018", s2_images, value = TRUE)
s2_bands <- grep("B02|B03|B04|B08", s2_images, value = TRUE)
s2_bands <- grep("10m", s2_bands, value = TRUE)
scl_images <- grep("SCL", s2_images, value = TRUE)
scl_images <- grep("20m", scl_images, value = TRUE)
s2_images <- c(s2_bands, scl_images)

dates <- lapply(s2_images, function(p){
  strsplit(basename(p), "_")[[1]][2]
}) |>
  unlist() |>
  unique()
# select every other date
dates <- dates[c(T,F)]

s2_images <- grep(paste(dates, sep = "", collapse = "|"), s2_images, value = TRUE)
dir.create("inst/extdata/Sentinel2", recursive = TRUE, showWarnings = FALSE)
aoi <- st_read("inst/aoi.gpkg", quiet = TRUE)

with_progress({
  p <- progressor(steps = length(s2_images))

  future_walk(s2_images, function(image){1+1
    img <- rast(image)
    aoi_tmp <- st_transform(aoi, st_crs(img))
    img <- crop(img, aoi_tmp)

    filename = file.path("./inst/extdata/Sentinel2", basename(image))
    if (file.exists(filename)) return()
    if (length(grep("SCL", filename)) == 0){
      writeRaster(img, filename, datatype = "INT2U", filetype = "JP2OpenJPEG", overwrite=TRUE, gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2"))
    } else {
      writeRaster(img, filename, datatype = "INT1U", filetype = "JP2OpenJPEG", overwrite=TRUE, gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2"))
    }
    p()
  })
})

xmls <- list.files("inst/extdata/Sentinel2/", pattern = ".xml$", full.names = T)
file.remove(xmls)
