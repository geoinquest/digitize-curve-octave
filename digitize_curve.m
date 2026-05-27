function xy = digitize_curve(x_range, y_range, image_file)
  % Digitize a curve from an image using four plot-corner clicks.
  %
  % Usage:
  %   xy = digitize_curve([xleft xright], [ybottom ytop]);
  %   xy = digitize_curve([xleft xright], [ybottom ytop], "my_plot.png");
  %
  % Corner click order:
  %   1. lower-left  corner of plot area
  %   2. lower-right corner of plot area
  %   3. upper-right corner of plot area
  %   4. upper-left  corner of plot area

  if nargin >= 1 && ischar(x_range) && strcmp(x_range, "__selftest__")
    xy = run_selftest();
    return;
  endif

  if nargin < 2
    error("Usage: xy = digitize_curve([xleft xright], [ybottom ytop], optional_image_file)");
  endif

  x_range = validate_range(x_range, "x");
  y_range = validate_range(y_range, "y");
  xleft = x_range(1);
  xright = x_range(2);
  ybottom = y_range(1);
  ytop = y_range(2);

  if nargin < 3 || isempty(image_file)
    image_file = choose_default_png();
  endif

  if ! exist(image_file, "file")
    error("Image file not found: %s", image_file);
  endif

  img = imread(image_file);

  figure("name", "Curve digitizer");
  clf;
  imagesc(img);
  colormap(gray(256));
  axis image ij;
  hold on;
  prepare_annotation_panel(size(img));
  title(sprintf("Image: %s", image_file), "interpreter", "none");

  corners = pick_plot_corners(xleft, xright, ybottom, ytop, size(img));
  curve_px = pick_curve_points();

  if isempty(curve_px)
    xy = zeros(0, 2);
    disp("No curve points were captured.");
    return;
  endif

  uv = image_to_unit_square(curve_px, corners);
  xy = [xleft + uv(:, 1) .* (xright - xleft), ...
        ybottom + uv(:, 2) .* (ytop - ybottom)];

  csv_file = "digitized_curve.csv";
  write_xy_csv(csv_file, xy);

  disp("Digitized XY points:");
  disp(xy);
  fprintf("Saved %d points to %s\n", rows(xy), csv_file);
endfunction

function uv = run_selftest()
  % Internal non-interactive test hook.
  %
  % The main workflow uses ginput(), so it cannot be fully tested in a
  % headless terminal. This helper tests the parts that can be checked
  % without mouse clicks:
  %   1. range validation accepts row and column vectors
  %   2. inverse corner mapping sends each clicked corner to the expected
  %      unit-square coordinate
  %   3. the geometric center of a slightly skewed quadrilateral maps to
  %      approximately (u, v) = (0.5, 0.5)
  assert(validate_range([0, 10], "x"), [0, 10]);
  assert(validate_range([20; 80], "y"), [20, 80]);

  % Corners are ordered exactly like the user clicks them:
  % lower-left, lower-right, upper-right, upper-left. The numbers here are
  % image/pixel coordinates, not data coordinates.
  corners = [10, 100; 210, 100; 220, 20; 20, 20];

  % Test points include the four corners plus one point in the middle.
  pts = [
    10, 100;
    210, 100;
    220, 20;
    20, 20;
    115, 60
  ];

  uv = image_to_unit_square(pts, corners);
  assert(uv(1, :), [0, 0], 1e-9);
  assert(uv(2, :), [1, 0], 1e-9);
  assert(uv(3, :), [1, 1], 1e-9);
  assert(uv(4, :), [0, 1], 1e-9);
  assert(uv(5, :), [0.5, 0.5], 1e-9);
endfunction

function write_xy_csv(csv_file, xy)
  % Write the digitized data to a simple CSV file.
  %
  % Octave's save("-ascii", ...) writes whitespace-delimited text, even if
  % the filename ends in .csv. This helper writes true comma-separated rows
  % and includes a small x,y header so the file opens cleanly in spreadsheet
  % programs.
  fid = fopen(csv_file, "w");
  if fid < 0
    error("Could not write output file: %s", csv_file);
  endif

  % unwind_protect guarantees fclose() runs even if fprintf() errors. That
  % keeps the output file handle from being left open in an Octave session.
  unwind_protect
    fprintf(fid, "x,y\n");

    % xy.' transposes the N-by-2 point matrix into 2-by-N. fprintf consumes
    % columns in order, producing one "x,y" line per original point.
    fprintf(fid, "%.15g,%.15g\n", xy.');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function image_file = choose_default_png()
  % Pick the image file when the caller did not pass one explicitly.
  %
  % This keeps the common case short:
  %   xy = digitize_curve([xleft xright], [ybottom ytop])
  % If there is one PNG in the current folder, it is used automatically. If
  % there are several, the user chooses from a numbered list.
  pngs = dir("*.png");

  if isempty(pngs)
    error("No PNG files found in the current folder.");
  elseif numel(pngs) == 1
    image_file = pngs(1).name;
    fprintf("Using PNG file: %s\n", image_file);
  else
    fprintf("PNG files in this folder:\n");
    for k = 1:numel(pngs)
      fprintf("  %d: %s\n", k, pngs(k).name);
    endfor

    idx = input("Choose image number: ");
    if ! isscalar(idx) || idx < 1 || idx > numel(pngs) || idx != fix(idx)
      error("Invalid image number.");
    endif
    image_file = pngs(idx).name;
  endif
endfunction

function range = validate_range(range, axis_name)
  % Validate and normalize an axis range.
  %
  % The public API expects a two-value numeric vector:
  %   x_range = [xleft xright]
  %   y_range = [ybottom ytop]
  % The vector may be a row or column; this helper returns a row vector so
  % later code can consistently use range(1) and range(2).
  if ! isnumeric(range) || numel(range) != 2 || range(1) == range(2)
    error("%s_range must be two different numeric values, for example [0 10].", ...
          axis_name);
  endif

  range = range(:).';
endfunction

function prepare_annotation_panel(img_size)
  % Reserve blank space to the right of the image for corner annotations.
  %
  % imagesc() initially makes the axes just large enough for the image. The
  % corner labels can cover the plot if placed directly near each point, so
  % this expands the x-axis limits and draws a vertical divider after the
  % image. The extra area is still part of the same axes, which makes it easy
  % to place text using image/pixel coordinates.
  img_height = img_size(1);
  img_width = img_size(2);

  % Use either 260 pixels or 35% of the image width, whichever is larger.
  % This leaves enough room for three-line coordinate labels.
  panel_width = max(260, 0.35 * img_width);

  % axis image ij sets the image y-axis downward; these limits preserve that
  % orientation while extending only the right side for annotations.
  xlim([0.5, img_width + panel_width]);
  ylim([0.5, img_height + 0.5]);

  % Divider between the real image and the annotation area.
  line([img_width + 0.5, img_width + 0.5], [0.5, img_height + 0.5], ...
       "color", [0.55, 0.55, 0.55], "linewidth", 1);

  % Panel heading.
  text(img_width + 18, 30, "Picked plot corners", ...
       "color", "r", "fontweight", "bold", "interpreter", "none");
endfunction

function corners = pick_plot_corners(xleft, xright, ybottom, ytop, img_size)
  % Interactively collect the four corners of the plot area.
  %
  % The function returns a 4-by-2 matrix of image coordinates:
  %   [pixel_x, pixel_y]
  % in the same order as the corner_names list below. That fixed ordering is
  % important because the interpolation math assumes:
  %   p00 = lower-left, p10 = lower-right,
  %   p11 = upper-right, p01 = upper-left.
  corner_names = {
    "lower-left",
    "lower-right",
    "upper-right",
    "upper-left"
  };
  data_coords = [
    xleft, ybottom;
    xright, ybottom;
    xright, ytop;
    xleft, ytop
  ];

  % Give each corner a stable color. The same color is used for the marker,
  % small on-image number, and annotation text.
  corner_colors = get_corner_colors();

  corners = zeros(4, 2);

  for k = 1:4
    color = corner_colors(k, :);

    % The prompt uses the actual data coordinate values supplied by the user,
    % not generic xmin/xmax/ymin/ymax wording.
    title(sprintf("Click the %s plot corner at xy=(%.6g, %.6g)", ...
                  corner_names{k}, data_coords(k, 1), data_coords(k, 2)));
    [x, y, button] = ginput(1);

    % ginput returns an empty button if the figure is closed or the selection
    % is cancelled. Stop immediately so the caller does not continue with an
    % incomplete calibration.
    if isempty(button)
      error("Corner selection cancelled.");
    endif

    % Store the raw image coordinate exactly as ginput reports it.
    corners(k, :) = [x, y];

    % Mark the clicked corner with a plus sign and a small number. Detailed
    % coordinate text is kept outside the plot by annotate_corner().
    plot(x, y, "+", "color", color, "markersize", 11, "linewidth", 2.5);
    text(x, y, sprintf(" %d", k), ...
         "color", color, "fontweight", "bold", "interpreter", "none");
    annotate_corner(k, corner_names{k}, [x, y], data_coords(k, :), ...
                    img_size, color);
  endfor

  % Draw the selected plot boundary so the user can visually check the corner
  % order and shape before picking curve points.
  plot([corners(:, 1); corners(1, 1)], ...
       [corners(:, 2); corners(1, 2)], ...
       "r-", "linewidth", 1.5);
endfunction

function colors = get_corner_colors()
  % RGB colors for the four plot corners.
  %
  % Rows correspond to:
  %   1 lower-left, 2 lower-right, 3 upper-right, 4 upper-left.
  % Values are normalized RGB triples in the Octave/MATLAB 0..1 range.
  colors = [
    0.85, 0.10, 0.10;
    0.00, 0.45, 0.85;
    0.00, 0.55, 0.20;
    0.75, 0.25, 0.85
  ];
endfunction

function annotate_corner(k, corner_name, pixel_coord, data_coord, img_size, color)
  % Write a corner's coordinates in the side panel, outside the plot area.
  %
  % pixel_coord is the clicked location in image axes.
  % data_coord is the real plot coordinate represented by that corner.
  % The annotation is intentionally not connected by a dashed line; only the
  % matching color ties it back to the point marker.
  img_height = img_size(1);
  img_width = img_size(2);

  % The text panel begins just to the right of the image. Each corner gets a
  % vertical slot with enough room for three text lines.
  label_x = img_width + 18;
  label_y = 65 + (k - 1) * 58;

  % Use interpreter="none" so underscores, parentheses, and decimal notation
  % display literally instead of being interpreted as TeX commands.
  text(label_x, label_y, ...
       sprintf("%d %s\nxy=(%.6g, %.6g)\npx=(%.1f, %.1f)", ...
               k, corner_name, data_coord(1), data_coord(2), ...
               pixel_coord(1), pixel_coord(2)), ...
       "color", color, "fontweight", "bold", "interpreter", "none", ...
       "verticalalignment", "top");
endfunction

function pts = pick_curve_points()
  % Interactively collect points along the curve.
  %
  % Mouse controls:
  %   MB1 / left click   : append a point
  %   MB2 / middle click : remove the most recently added point
  %   MB3 / right click  : finish capture
  %
  % The returned pts matrix contains raw image coordinates only. Conversion to
  % real plot coordinates happens later, after all clicks are collected.
  pts = zeros(0, 2);

  % Handles for the temporary preview graphics. They are deleted and redrawn
  % after each edit so undoing the last point updates the display cleanly.
  h_pts = [];
  h_line = [];

  title({"Pick curve points", ...
         "MB1: add point    MB2: remove last point    MB3: finish"});

  while true
    [x, y, button] = ginput(1);

    % Right-click, closing the figure, or pressing a terminating key ends the
    % capture loop.
    if isempty(button) || button == 3
      break;
    elseif button == 1
      % Add the new clicked image coordinate to the end of the list.
      pts(end + 1, :) = [x, y];
    elseif button == 2
      % Middle-click acts like a one-step undo. Do nothing if there are no
      % points yet.
      if ! isempty(pts)
        pts(end, :) = [];
      endif
    else
      fprintf("Ignoring button/key code %g. Use MB1, MB2, or MB3.\n", button);
    endif

    % Refresh the cyan preview after every add/remove operation.
    [h_pts, h_line] = redraw_curve_selection(pts, h_pts, h_line);
  endwhile

  % One final redraw leaves the captured path visible after the loop exits.
  [h_pts, h_line] = redraw_curve_selection(pts, h_pts, h_line);
  title(sprintf("Captured %d curve points", rows(pts)));
endfunction

function [h_pts, h_line] = redraw_curve_selection(pts, h_pts, h_line)
  % Redraw the curve-picking preview.
  %
  % The simplest way to support "remove last point" is to delete the old
  % preview graphics and replot from the current pts matrix. This avoids
  % manually editing XData/YData, which can differ slightly across Octave
  % graphics toolkits.
  if ! isempty(h_pts) && ishandle(h_pts)
    delete(h_pts);
  endif
  if ! isempty(h_line) && ishandle(h_line)
    delete(h_line);
  endif

  h_pts = [];
  h_line = [];

  % When no points exist, there is nothing to draw. Return empty handles so
  % the next call knows there are no old preview objects to delete.
  if ! isempty(pts)
    % Draw a connecting line plus filled circular markers so the clicked path
    % is easy to inspect as it grows.
    h_line = plot(pts(:, 1), pts(:, 2), "c-", "linewidth", 1.5);
    h_pts = plot(pts(:, 1), pts(:, 2), "co", ...
                 "markersize", 6, "markerfacecolor", "c");
  endif
endfunction

function uv = image_to_unit_square(pts, corners)
  % Convert image points into normalized plot coordinates.
  %
  % Output uv has the same number of rows as pts:
  %   u = 0 at xleft,  u = 1 at xright
  %   v = 0 at ybottom, v = 1 at ytop
  %
  % The actual data coordinates are computed later by scaling u and v by the
  % user-supplied x/y ranges.
  uv = zeros(rows(pts), 2);

  % Each point is inverted independently because a skewed four-corner mapping
  % is bilinear, not a single global linear matrix.
  for k = 1:rows(pts)
    uv(k, :) = inverse_bilinear_point(pts(k, :), corners);
  endfor
endfunction

function uv = inverse_bilinear_point(pt, corners)
  % Invert the bilinear map from normalized plot coordinates to image pixels.
  %
  % Forward map:
  %   image_point =
  %     (1-u)(1-v) p00 + u(1-v) p10 + uv p11 + (1-u)v p01
  %
  % Here:
  %   p00 = lower-left,  p10 = lower-right,
  %   p11 = upper-right, p01 = upper-left.
  %
  % Because the user may click a skewed quadrilateral, u/v cannot always be
  % recovered with one affine solve. This helper starts with an affine guess
  % and refines it with Newton iterations.
  p00 = corners(1, :);
  p10 = corners(2, :);
  p11 = corners(3, :);
  p01 = corners(4, :);

  % Initial guess: pretend the left/right and bottom/top edges form an affine
  % parallelogram. This is exact for rectangular or parallelogram plots and is
  % usually close for mildly skewed scanned images.
  axes_matrix = [p10(:) - p00(:), p01(:) - p00(:)];
  if abs(det(axes_matrix)) > eps
    uv = (axes_matrix \ (pt(:) - p00(:))).';
  else
    % Degenerate corner clicks make the affine guess impossible. Start from
    % the center so Newton still has a defined initial value.
    uv = [0.5, 0.5];
  endif

  for iter = 1:20
    u = uv(1);
    v = uv(2);

    % Forward bilinear interpolation from current (u, v) to image pixels.
    mapped = (1 - u) * (1 - v) * p00 ...
             + u * (1 - v) * p10 ...
             + u * v * p11 ...
             + (1 - u) * v * p01;

    % Residual is how far the current mapped point is from the clicked point.
    residual = (mapped - pt).';

    % Stop once the image-space error is essentially zero.
    if norm(residual) < 1e-10
      break;
    endif

    % Jacobian columns are derivatives of the forward map with respect to u
    % and v. Newton uses this local slope to improve the current estimate.
    dpdu = (1 - v) * (p10 - p00) + v * (p11 - p01);
    dpdv = (1 - u) * (p01 - p00) + u * (p11 - p10);
    jacobian = [dpdu(:), dpdv(:)];

    % If the local geometry is nearly singular, use a pseudo-inverse instead
    % of a direct solve so the code degrades gracefully.
    if rcond(jacobian) < 1e-12
      step = pinv(jacobian) * residual;
    else
      step = jacobian \ residual;
    endif

    % Newton update: subtract the correction from the current estimate.
    uv = uv - step.';
  endfor
endfunction

% Octave's built-in test command runs this block. It exercises the
% non-interactive self-test path above.
%!test
%! uv = digitize_curve("__selftest__");
%! assert(rows(uv), 5);
