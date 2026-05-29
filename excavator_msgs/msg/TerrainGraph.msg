# Top-level terrain graph observation for excavator perception.
#
# Status: draft v0.1.0. This mirrors the Unity-side
# terrain_graph_observation_v0 JSON schema closely enough for Track 1 ROS 2
# publisher prototyping. Field additions are expected while the perception
# schema is still experimental.

std_msgs/Header header

string schema_version
int64 frame
float64 sim_time_sec
string scenario_id

TerrainGraphMetadata metadata
TerrainGraphNode[] nodes
TerrainGraphEdge[] edges
