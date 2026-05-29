# One frame-local terrain graph node.
#
# id is dense within a TerrainGraph message and is not stable across frames.

int32 id
string kind

float32 x
float32 y
float32 z

float32 vx
float32 vy
float32 vz

float32 radius
float32 mass
float32 height
float32 depth_below_surface

int32 surface_i
int32 surface_j
int32 source_index

bool is_dynamic
bool is_tool
bool is_in_roi

float32 boundary_normal_x
float32 boundary_normal_y
float32 boundary_normal_z
