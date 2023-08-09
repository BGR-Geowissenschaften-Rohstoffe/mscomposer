# mscomposer 0.1.0

* Added a `NEWS.md` file to track changes to the package.
* First release of `{mscomposer}` includes following functionality:
  * Supply image files and format subject to your spatio-temporal extent
    of interest
  * Supply a CRS and spatial resolution for the targeted output as well as
    aggregation and resampling methods to align the original pixels with your
    desired extent
  * Determine the initial temporal resolution of your cube view. Depending
    on subsequent choices, this also might be the temporal resolution of the final 
    output
  * Include only those bands in the calculation that you are interested in and 
    that you might require to calculate spectral indices
  * Supply one or more reducer function which optionally will be applied to the
    initial time dimension to collapse your data into a single composite
  * Optionally, supply formulas for spectral indices or other band arithmetics
    to enrich your data with custom bands
  * Optionally, apply pixel-wise filters based on logical expressions on the
    original or custom bands. Only those pixels will be retained, where the
    supplied logical expressions evaluate to TRUE
  * Additional arguments for the creation of the output GTiff, e.g. for the 
    creation of overviews or file compression
