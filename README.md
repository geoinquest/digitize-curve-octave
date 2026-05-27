# digitize-curve-octave
Octave script that digitizes curve data from an image (plot, map, ...) 


- Uses [xleft xright] and [ybottom ytop] as arguments as well as image
- Lets user click four plot corners, then curve points.
- Uses + markers for corners.
- Uses unique corner colors for markers and annotation text.
- Displays corner coordinate annotations outside the plot area.
- Uses MB1/MB2/MB3 for add/remove/finish curve capture.
- Converts picked image points to real XY coordinates.
- outputs a Nx2 array (X, Y values)
- optional image input as 3rd argument
- optional CSV output name/path as 4th argument
- Added comments to helper functions.
- Verified Octave self-test passes on macos


Usage: xy= digitize_curve( [0,70], [5486,0]) to use the default image
