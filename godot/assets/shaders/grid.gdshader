shader_type spatial;

// An imperceptably small value used for fuzzy float comparisons
const float EPSILON = 0.0001;

/** The first grid cell color. */
uniform vec3 color_a: source_color = vec3(0.88, 0.91, 0.91);

/** The second grid cell color. */
uniform vec3 color_b: source_color = vec3(0.78, 0.80, 0.86);

/** How many cells per UV unit. */
uniform float cells = 4.0;

/** Whether to use local (false) or world (true) coordinates. */
uniform bool world_coordinates = false;

varying vec3 local_position;

/**
 * Checks if two values are approximately equal.
 */
bool is_equal_approx(float a, float b) {
	return abs(a - b) <= EPSILON;
}

/**
 * Applies a bias to the given value to compensate for floating point
 * imprecision that would cause floor(value) to shift between two integers.
 */
float apply_floor_bias(float value) {
	if (floor(value) != floor(value + EPSILON)) {
		value += EPSILON;
	}
	return value;
}

/**
 * Applies a bias to the components of the given vector to compensate for
 * floating point imprecision that would cause floor(component) to shift between
 * two integers.
 */
vec3 apply_floor_bias(vec3 value) {
	value.x = apply_floor_bias(value.x);
	value.y = apply_floor_bias(value.y);
	value.z = apply_floor_bias(value.z);
	
	return value;
}

/** Snaps the given position to the integer grid. */
vec3 snap_to_grid(vec3 position) {
	// Calculate an offset to ensure the grid is centered on even sizes (ie a
	// grid of 4 cells will have all 4 cells fully visible on a 1m plane)
	vec3 grid_offset = vec3(1.0 / cells);
	
	// Scale and offset the position to the grid
	vec3 grid_position = (position - grid_offset) * cells;
	
	// Bias coordinates to compensate for floating point imprecision - not doing
	// this will cause flickering along planes perfectly between two cells
	grid_position = apply_floor_bias(grid_position);
	
	// Snap the position to the cell boundaries
	return floor(grid_position);
}

/** Samples the grid color at the given position. */
vec3 sample_3d_grid(vec3 position) {
	// Get the integer index of the row, column, and layer for each grid cell
	vec3 cell_index = snap_to_grid(position);
	
	// Determine whether each row/column/layer is even (0) or odd (1) by its
	// index
	vec3 cell_parity = mod(cell_index, 2.0);
	
	// If the row and column have the same parity then their cells form a
	// diagonal line in their plane. To apply to 3D, invert this check every
	// other layer so the diagonal line shifts one position.
	bool is_diagonal_cell = is_equal_approx(cell_parity.x, cell_parity.z) != is_equal_approx(cell_parity.y, 0.0);
	
	// Assign one color if the cell forms a diagonal line; otherwise, use the
	// other color
	return mix(color_a, color_b, float(is_diagonal_cell));
}

void vertex() {
	// Provide the model vertex position to the fragment shader.
	// Required because fragment's VERTEX is in view-space and while it does
	// have an inverse view matrix to convert to world coords, it doesn't have
	// an inverse model matrix to convert to local coords.
	// 
	// The inverse can be calculated but all the computations to derive the
	// local coordinates from screen coordinates are seemingly more expensive
	// than just supplying the computation already present in the vertex shader.
	local_position = VERTEX;
}

void fragment() {
	vec3 position = local_position;
	if (world_coordinates) {
		vec4 world_position = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
		position = world_position.xyz;
	}
	
	ALBEDO = sample_3d_grid(position);
}
