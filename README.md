# sim-protocol — Shared Protocol and Schema (Repo C)

Owner: joint (Unity/AGX team + Python/testbed team)
Rule: this repo is the shared contract surface for Repo A and Repo B.

Current status:
- Repo C has been updated to match the current Repo B binary step-ack protocol.
- Anything still uncertain in Repo B is marked provisional here instead of being
  guessed or frozen as a fake constant.
- Current shared docs are also aligned to Repo A's live AGX HDF5 schema and
  eval artifact names.
- Repo A current business baseline is the rerecord `v1` line
  (`teleop_v1 / act_agx_v1 / eval_agx_v1`), while `fulltest` remains the main
  historical comparison set for `qpos` vs `qpos+qvel`.

## Contents

| File | Purpose |
| --- | --- |
| [protocol.md](protocol.md) | Wire protocol for `GET_INFO`, `RESET`, `STEP` |
| [schema.md](schema.md) | HDF5 episode schema v1.1 |
| [constants.yaml](constants.yaml) | Shared constants and ordering definitions |
| [eval_suite_v0.yaml](eval_suite_v0.yaml) | Fixed eval suite skeleton for AGX excavation |
| [platform_switch_windows.md](platform_switch_windows.md) | Shared checklist for migrating Repo A + Repo B to Windows without changing the Repo C contract |

## Quick Reference

Action vector:
```text
[swing_speed_cmd, boom_speed_cmd, stick_speed_cmd, bucket_speed_cmd]
```

qpos vector:
```text
[swing_position_norm, boom_position_norm, stick_position_norm, bucket_position_norm]
```

qvel vector:
```text
[swing_speed, boom_speed, stick_speed, bucket_speed]
```

env_state:
```text
index 0 = mass_in_bucket_kg
index 1 = excavated_mass_kg
index 2 = mass_in_target_box_kg
index 3 = deposited_mass_in_target_box_kg
index 4 = min_distance_to_target_m
index 5 = target_hard_collision_count
index 6 = target_contact_max_normal_force_n
index 7 = min_distance_to_dig_area_m
index 8 = bucket_depth_below_dig_area_plane_m
index 9 = target_horizontal_distance_m
index 10 = bucket_height_above_target_rim_m
index 11 = bucket_over_target_footprint_mask
index 12 = dump_clearance_ok_mask
index 13 = bucket_dump_area_relative_x_m
index 14 = bucket_dump_area_relative_z_m
index 15 = bucket_dump_area_footprint_outside_distance_m
```

Current distance semantics:
- `min_distance_to_target_m` reports legacy approximate bucket-proxy-to-active-target-distance-geometry distance and is diagnostics-only for target safety
- `min_distance_to_dig_area_m` and `bucket_depth_below_dig_area_plane_m` are the DigArea good-start geometry signals used by Repo A reward gating
- `target_horizontal_distance_m`, `bucket_height_above_target_rim_m`,
  `bucket_over_target_footprint_mask`, `dump_clearance_ok_mask`, and the three
  `bucket_dump_area_*` fields are the explicit target/dump-area geometry
  contract used by Repo A target-safety reward, filtering, and scripted dump guards
- target-safety logic must not fall back from those explicit fields to
  `min_distance_to_target_m`

Step-ack hard rule:
```text
STEP_RESP.step_id must equal STEP_REQ.step_id.
```

Contract boundary:
- Live Repo A <-> Repo B interaction is the binary wire protocol in `protocol.md`.
- Offline collected data is the HDF5 dataset contract in `schema.md`.
- Repo B may emit local `metadata.json` / `steps.jsonl` / raw RGB sidecar files,
  but those are auxiliary Unity-native exports, not the shared live contract.
- V0 task scope is fixed-position / stationary digging only; drive / steer /
  track motion are intentionally excluded from the current shared action space.
- Platform migration guidance for moving Repo A + Repo B to Windows lives in
  `platform_switch_windows.md`; that file is operational guidance, not a new
  protocol layer.

Operational mapping:
- `tb-record-teleop --config testbed/configs/teleop_v1.yaml`
  is the current Repo A baseline data-collection command
- `tb-train --config testbed/configs/act_agx_v1.yaml`
  is the current Repo A business-baseline training command
- `tb-eval --config testbed/configs/eval_agx_v1.yaml`
  is the current Repo A business-baseline live evaluation command
- `tb-record-teleop --config testbed/configs/teleop_v2_1_multi_raw.yaml`
  is the current Repo A V2.1 Stage-1 multicycle raw-recording entry; it stops
  on the third detected `dump_end` and uses `max_steps = 4000` only as a guardrail
- `tb-label-v2_1 --dataset-dir data/agx_teleop_v2_1_multi_raw`
  is the current Repo A offline step that writes Stage-1 multicycle `/v2`
  labels into a sibling relabeled dataset copy
- `tb-eval --config testbed/configs/eval_agx_v2_1_stage1.yaml`
  is the current Repo A V2.1 Stage-1 live evaluation entry
- the older phase-1 single-cycle `teleop_v2_cycle_*` and `tb-label-v2`
  entrypoints have been removed from the current branch and now live only in
  repository history
- `tb-train --config testbed/configs/act_agx_fulltest_qvel.yaml`
  remains the main `qpos+qvel` comparison command on the older `fulltest` dataset

## What Is Settled

- Transport is binary framed TCP, not JSON.
- Header size is 16 bytes with CRC32 over payload bytes.
- `GET_INFO_RESP` is a binary field sequence with string arrays and camera
  descriptors.
- `qpos` is currently 4D in the running Unity implementation.
- FPV transport is raw RGB in V0.
- Action semantics are `actuator_speed_cmd`.
- V0 action dimension is intentionally 4, not 6.
- `RESET_REQ.reset_pose` and `RESET_REQ.reset_terrain` are independent in the
  current Unity implementation; pose-only reset must not implicitly re-sculpt terrain.
- Terrain reset is handled by Unity `ResetTerrain` / `SceneResetService`; the
  excavation metrics component is no longer part of the terrain reset path.
- When `RESET_REQ.reset_terrain = true`, Unity is expected to rebuild the
  deformable terrain state so bucket-trapped soil particles are cleared back to
  the initial terrain baseline.
- Repo B baseline consumes pending requests on `Update`.
- Transport scheduling experiments belong to dedicated transport branches and do
  not change the baseline wire contract defined in Repo C.
- V0 success is target-centric:
  `deposited_mass_in_target_box_kg >= 100.0 kg` for `25` consecutive steps
  within the `1000`-step episode.
- Repo B now exports active-target hard-collision summary metrics:
  `target_hard_collision_count` and `target_contact_max_normal_force_n`.
- Repo B now exports explicit active-target dump geometry:
  `target_horizontal_distance_m`, `bucket_height_above_target_rim_m`,
  `bucket_over_target_footprint_mask`, `dump_clearance_ok_mask`, and the three
  `bucket_dump_area_*` local geometry fields.
- `target_hard_collision_count` is cumulative within the episode.
- one continuous excavator-vs-target contact session increments that count at
  most once.
- the count can increase again only after the excavator leaves the target and
  later touches it again.
- The monitored collision body should represent the active dump-area target
  geometry in the current E85 scene.
- Repo A HDF5 v1.1 episodes now also carry demo-level metadata and config
  snapshot attrs such as `operator_id`, `session_id`, `notes`,
  `record_config_path`, and `record_config_yaml`.
- Repo A currently applies a fixed `0.75` per-step hard-collision penalty only
  when the cumulative `target_hard_collision_count` increases on that step.
- Unity `STEP_RESP.reward` now mirrors
  `deposited_mass_in_target_box_kg` as a backup success proxy on the wire.
- Repo A still computes the primary AGX mission reward locally from the
  recorded `env_state` series.
- Repo A only opens the shaped `loading -> approaching_target -> depositing`
  reward chain after a qualified DigArea good start when the two DigArea
  geometry fields are present on the wire.
- Repo A target-safety training and scripted dump guards require the four
  explicit target-geometry fields; old 9-column data is legacy-only for this
  purpose and should not be mixed into target-safety training as a fallback.
- `RESET_REQ.scenario_id` is now operational in phase-1, but only as a minimal
  preset-routing key for `reset_terrain`, `reset_pose`, and `ActiveTargetIndex`.
- Repo A may attach an optional `/v2` add-only extension group to HDF5 episodes;
  this does not change the shared `schema_version = "1.1"` contract.

## What Is Still Provisional

- The exact semantic range for `swing_position_norm` is not a hard physical
  limit. It depends on the configured Unity normalization window.
- FPV width, height, and fps are runtime-advertised by `GET_INFO_RESP`; they
  should not be treated as globally fixed constants yet.
- Boom position/speed still comes from `BoomPrismatics[0]` in the current
  Unity implementation.
- TCP transport is still single-client sequential; dead client cleanup is in
  place, but there is no higher-level reconnect/session layer in Repo C.

## Versioning Rules

| Change | Required action |
| --- | --- |
| New optional response field | Keep backward compatible; no version bump required |
| New add-only env_state tail field | Preserve existing prefix order, update Repo C docs/constants, and feature-gate consumers |
| New required wire field | Bump protocol version and review jointly |
| Change existing vector ordering or prefix dimension | Bump protocol version and schema version |
| New required HDF5 field | Bump schema version |
| Remove an existing field | Not allowed without deprecation plan |

## Open Follow-Up

- Replace placeholder GitHub handles in `CODEOWNERS`.
- Wire Repo A to consume Repo C definitions instead of only mirroring Repo B.
- Decide whether Repo B's local JSON/RGB episode export should get an official
  conversion utility into the shared HDF5 schema.
- Revisit the current retained-target-mass success threshold only after more
  pilot episodes are collected under the current scene/material setup.
- Freeze a short written V0 benchmark task spec for start pose / terrain /
  episode packaging, since the control and evaluator contracts are now ahead of
  the task-sheet wording.
- Decide later whether a fuller collision/contact event export is needed beyond
  the current active-target hard-collision summaries.
