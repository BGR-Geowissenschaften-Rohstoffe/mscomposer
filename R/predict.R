#' Train a random forest model and predict on a raster
#'
#' This function can be used to train a basic random forest model based
#' on an sf-object with point location and specific measurements as well as
#' a raster dataset with predictors. You will have to specify the column name
#' of the variable to be modeled. The function returns a list with the predicted
#' raster, the model, an accuracy metrics object as well as the extracted
#' data object with the extracted predictors and the predictions and observations
#' at the point locations.
#'
#' @param samples An sf object containing only POINT geometries.
#' @param colname A charachter indicating an existing column in `samples` with the
#'   response variable. This variable must be `numeric`.
#' @param predictors A SpatRaster object with the predictor variables.
#' @param model_method Model type to be used for training. See \url{https://topepo.github.io/caret/available-models.html}.
#'   Note, that you might need to install additional dependencies before using any of
#'   the listed methods.
#' @param cv_method A method for `trainControl` indicating the cross-validation
#'   strategy to be used. Defaults to `LOOCV`, meaning Leave-One-Observation-Out
#'   Cross-Validation.
#'
#' @return A list object with names prediction, model, metrics, and data.
#' @export
#' @importFrom caret train postResample trainControl
#' @importFrom stats predict
#' @importFrom terra extract
#'
#' @examples
#' library(sf)
#' library(terra)
#' library(mscomposer)
#'
#' samples <- system.file("corg-simulated-sample.gpkg", package = "mscomposer") |>
#'   read_sf()
#' predictors <- system.file("soil-composite.tif", package = "mscomposer") |>
#'   rast()
#' results <- ms_predict(
#'   samples,
#'   "corg",
#'   predictors,
#'   model_method = "rf",
#'   cv_method = "LOOCV"
#'  )
#'
#' print(str(results, 1))
ms_predict <- function(
    samples,
    colname,
    predictors,
    model_method = "rf",
    cv_method = "LOOCV"
){

  if (!inherits(samples, "sf")){
    stop("Object samples must be of class 'sf'.")
  }

  if (any(st_geometry_type(samples) != "POINT")){
    stop("All geometries in samples must be of type POINT.")
  }

  if (!colname %in% names(samples)){
    stop(sprintf("Column '%s' does not exist in samples.", colname))
  }

  if (!inherits(samples[[colname]], "numeric")){
    stop("Class of data in the sample column must be of type 'numeric'.")
  }

  if(st_crs(samples) != st_crs(predictors)){
    warning("CRS of sf object and raster differ.\nTrying to transform the sf object.")
    sample <- st_transform(samples, st_crs(predictors))
  }

  obs <- samples[[colname]]
  if (any(is.na(obs))){
    stop(
      paste0("Response variable contains NAs.\n",
             "Please remove any observations with NA before using this function.")
    )
  }

  samples[colname] <- NULL

  predictors_df <- extract(
    predictors,
    samples
  )
  predictors_df$ID <- NULL

  if (any(is.na(predictors_df))){
    warning(
      paste0("Some predictors at sample locations are NA.\n",
             "Excluding those locations from model training.")
    )

    na_index <- which(is.na(rowSums(predictors_df)))
    predictors_df <- predictors_df[-na_index, ]
    samples <- samples[-na_index, ]
    obs <- obs[-na_index]

    if (nrow(predictors_df) == 0){
      stop("All samples contained at least one NA value. Please check your input raster.")
    }
    else {
      warning(
        sprintf("A total of %s points remained for training.", nrow(predictors_df))
      )
    }
  }

  model <- train(
    predictors_df,
    obs,
    method = model_method,
    trControl = trainControl(method = cv_method)
  )

  predictors_df$.preds <- predict(model, predictors_df)
  predictors_df$.obs <- obs
  samples <- cbind(samples, predictors_df)
  stats <- postResample(pred = samples$.preds, obs = samples$.obs)

  predicted <- terra::predict(predictors, model, na.rm = TRUE)
  names(predicted) <- paste0("prediction_", colname)

  list(
    prediction = predicted,
    model = model,
    metrics = stats,
    data = samples
  )

}

