library(sf)
library(dplyr)
library(terra)
library(raster)
library(gdalcubes)
library(mscomposer)
library(virtualspecies)

# create soil composite
s2_files <- list.files("inst/extdata/Sentinel2/", pattern = ".jp2$", full.names = TRUE, recursive = TRUE)
format <- system.file("Sentinel2_L2A_flat.json", package = "mscomposer")
aoi <- system.file("aoi_S2.gpkg", package = "mscomposer") |> st_read()
cv <- view(
  aoi,
  dt = "P3M",
  dx = 10,
  dy = 10,
  srs = st_crs("EPSG:32632"),
  agg = "min",
  rsmp = "bilinear",
  start = "2018-01-01",
  end = "2018-12-31")

outdir <- file.path(tempdir(), "mscomposer")
dir.create(outdir)

s2_filt <- compose(
  s2_files,
  format = format,
  view = cv,
  mask = image_mask("SCL", values=c(1,3,6,8,9,10,11)),
  bands = c("B02", "B03", "B04", "B08"),
  indices = list(NDVI = "(B08-B04)/(B08+B04)"),
  filters = list(NDVI = "NDVI < 0.4"),
  reducers = "median",
  prefix = "soil",
  outdir = outdir
)

(s2_filt <- rast(s2_filt[1]))
writeRaster(s2_filt, filename = "inst/soil-composite.tif", overwrite = TRUE)

# simulate response
set.seed(42)
relationship <- generateSpFromPCA(
  stack(s2_filt),
  rescale = TRUE,
  means = c(3,1),
  sds = c(2,2),
  plot = FALSE
)

response <- terra::rast(relationship$suitab.raster)
response <- response / 10
#writeRaster(response, filename =  "inst/corg-simulated-response.tif", overwrite = TRUE)
set.seed(43)
sample <- spatSample(response, size = 60, method = "random", na.rm = TRUE, as.points = TRUE, xy=TRUE)
sample |>
  st_as_sf() |>
  rename(corg = layer) |>
  mutate(ID = 1:nrow(sample)) |>
  st_write("inst/corg-simulated-sample.gpkg", delete_dsn = TRUE)
