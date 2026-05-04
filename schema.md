# schema.md — HDF5 Episode Dataset Schema v1.1

Repo: sim-protocol (Repo C - shared)
Last updated: 2026-04-24
Owner: joint (Unity/AGX team + Python/testbed team)
Rule: add-only. Never remove or rename existing datasets/groups.

This document is aligned to the current Repo A recorder/backend behavior and the
current Repo B observation contract.

Important boundary:
- This schema defines the offline dataset artifact used for training, replay,
  and evaluation.
- It is not the live interaction protocol between Repo A and Repo B.
- Repo B may also emit local `metadata.json` / `steps.jsonl` / raw RGB exports
  for debugging or conversion, but those files are auxiliary and are not the
  canonical shared dataset contract.
- Repo A may also attach an optional `/v2` add-only extension group for its
  own Stage-1 V2.1 multicycle labels. That extension is intentionally optional
  and does not bump `schema_version` beyond `"1.1"`.

## 1. File Layout

```text
episode_XXXX.hdf5
├── metadata/
├── timestamps/
├── action_source/
├── observations/
│   ├── qpos
│   ├── qvel
│   ├── env_state
│   └── images/
│       └── fpv
├── action
├── rewards
└── v2/                    optional Repo A extension
```

## 2. /metadata

Stored as HDF5 attributes under `/metadata`.

### Required for new AGX V0 datasets

| Attribute | Type | Notes |
| --- | --- | --- |
| `schema_version` | string | `"1.1"` |
| `task_name` | string | example: `"agx_excavation_teleop"` |
| `sim_backend` | string | `"agxunity"` |
| `seed` | int32 | reset seed used for the episode |
| `param_version` | string | example: `"v0"` or `"v1"` |
| `timestamp` | string | ISO 8601 |
| `control_hz` | int32 | currently `50` |
| `dt` | float32 | currently `0.02` |
| `action_semantics` | string | `"actuator_speed_cmd"` |
| `camera_names` | string | current Repo A stores comma-separated names |
| `image_format` | string | `"raw_rgb"` in V0 |

### Optional / recommended

| Attribute | Type | Notes |
| --- | --- | --- |
| `protocol_version` | string | example: `"agx-sim/v0"` |
| `camera_width` | int32 | runtime-specific; not yet guaranteed in every writer |
| `camera_height` | int32 | runtime-specific; not yet guaranteed in every writer |
| `camera_fps` | float32 | runtime-advertised camera fps |
| `camera_row_order` | string | current V0 is `"top_to_bottom"` |
| `operator_id` | string | teleop operator identity |
| `session_id` | string | grouping key |
| `notes` | string | free-form demo notes |
| `record_config_path` | string | Repo A recording config path snapshot |
| `record_config_yaml` | string | Repo A recording config YAML snapshot |
| `action_order` | string | comma-separated action names |
| `qpos_order` | string | comma-separated qpos names |
| `qvel_order` | string | comma-separated qvel names |
| `env_state_order` | string | comma-separated env_state names |
| `teleop_input` | string | `"joystick"` or `"keyboard"` |
| `deadzone` | float32[4] | per-axis teleop deadzone |
| `scale` | float32[4] | per-axis teleop scale |
| `limit` | float32[4] | per-axis teleop clip |
| `axis_map` | int32[4] | per-axis joystick mapping |
| `joystick_ids` | int32[4] | per-axis pygame joystick ids |
| `invert` | int32/bool[4] | per-axis invert flags |
| `key_speed` | float32 | keyboard teleop speed |
| `response_profile_enabled` | int32/bool | response-profile enabled flag |
| `response_profile_attack_rate` | float32[4] | joystick response-profile attack rate |
| `response_profile_release_rate` | float32[4] | joystick response-profile release rate |
| `response_profile_recenter_rate` | float32[4] | joystick response-profile recenter rate |
| `response_profile_exponent` | float32[4] | joystick response-profile exponent |
| `reset_mode` | string | example: `"baseline_fixed"` |
| `success` | int32/bool | episode-level success label written by Repo A |
| `n_steps` | int32 | convenience metadata |
| `v2_schema_version` | string | optional legacy Repo A phase-1 extension marker |
| `scenario_id` | string | optional Repo A experiment routing key |
| `recording_mode` | string | optional Repo A recording mode, current Stage-1 value `"teleop_multi_raw"` |
| `target_dump_count` | int32 | optional Repo A Stage-1 raw recording stop target |
| `stop_reason` | string | optional Repo A stop reason, such as `target_dump_count_reached` |
| `v2_enabled` | int32/bool | optional Repo A Stage-1 `/v2` enabled marker |
| `goal_token_dim` | int32 | optional Repo A goal-token width, current Stage-1 value `10` |
| `goal_token_version` | string | optional Repo A goal-token semantic version, current value `"v2_1a_sector10d"` |
| `phase_version` | string | optional Repo A phase semantic version, current value `"v2_1_mode_phase_7cls"` |
| `scenario_manifest_version` | string | optional Repo A Stage-1 scenario-manifest version |
| `transition_source` | string | optional Repo A transition-label source, current Stage-1 value `"none"` |
| `patch_grid_spec` | string | optional legacy Repo A phase-1 patch-grid metadata |
| `anchor_vocab_version` | string | optional legacy Repo A phase-1 ready-anchor vocab version |

## 3. /timestamps

For new AGX V0 datasets:

| Dataset | Shape | dtype | Notes |
| --- | --- | --- | --- |
| `step_id` | `(T,)` | int64 | required; matches `STEP_RESP.step_id` |
| `step_ns` | `(T,)` | int64 | recommended; wall-clock record timestamp |

## 4. /action_source

For new AGX V0 datasets:

| Dataset | Shape | dtype | Notes |
| --- | --- | --- | --- |
| `type` | `(T,)` | variable-length string | `"teleop"`, `"policy"`, `"scripted"` |
| `id` | `(T,)` | variable-length string | `"joystick"`, `"keyboard"`, or policy identifier |

Optional future extension:
- `latency_ms: (T,) float32`

## 4.1 Optional Repo A `/v2` extension

Repo A Stage-1 V2.1 may append an optional `/v2` group for offline multicycle
labels without changing the shared `schema_version`.

Current optional layout:

```text
/v2
├── step/
│   ├── cycle_id
│   ├── mode_id
│   ├── phase_id
│   ├── phase_progress
│   ├── goal_tokens
│   ├── planner_replan_mask
│   ├── qualified_dig_start_mask
│   ├── dump_start_mask
│   ├── dump_end_mask
│   ├── pause_mask
│   └── boundary_mask
└── cycle/
    ├── cycle_id
    ├── start_step
    ├── dump_end_step
    ├── end_step
    ├── curr_src_sector_id
    ├── curr_cut_depth_class
    ├── next_src_sector_id
    ├── next_cut_depth_class
    ├── dst_target_id
    ├── fill_peak_kg
    ├── deposit_delta_kg
    ├── peak_bucket_depth_m
    ├── collision_count_delta
    ├── transition_source
    ├── plan_source
    └── cycle_success
```

Stage-1 semantic notes:

- `goal_tokens` has shape `(T, 10)` and follows Repo A's sector-first V2.1 definition
- `mode_id` uses `0 = work`, `1 = transition`
- normal cycle boundaries still follow `cycle_i.start = qualified_dig_start(i)` and
  `cycle_i.end = qualified_dig_start(i+1)`
- raw teleop recording stops on the third detected `dump_end`, so Repo A allows a
  single terminal special-case where the final cycle closes at its own `dump_end_step`
- if a raw episode instead ends on `max_steps`, Repo A keeps the tail cycle incomplete
  with `end_step = -1` and `cycle_success = 0`

Contract rule:
- readers must continue to accept files that do not contain `/v2`
- `/v2` is add-only and optional; it is not part of the required cross-repo baseline

## 5. /observations

### 5.1 qpos

| Property | Value |
| --- | --- |
| Dataset path | `/observations/qpos` |
| Shape | `(T, 4)` |
| dtype | float32 |
| Range | normalized `[0, 1]` |

Column order:
```text
col 0: swing_position_norm
col 1: boom_position_norm
col 2: stick_position_norm
col 3: bucket_position_norm
```

Notes:
- `swing_position_norm` is present in the current Unity implementation
- its exact physical interpretation depends on the configured normalization
  window and should not be read as a true hard joint-limit mapping
- boom values currently come from `BoomPrismatics[0]`

### 5.2 qvel

| Property | Value |
| --- | --- |
| Dataset path | `/observations/qvel` |
| Shape | `(T, 4)` |
| dtype | float32 |
| Units | runtime-reported actuator speed units |

Column order:
```text
col 0: swing_speed
col 1: boom_speed
col 2: stick_speed
col 3: bucket_speed
```

### 5.3 env_state

| Property | Value |
| --- | --- |
| Dataset path | `/observations/env_state` |
| Shape | `(T, M)` |
| dtype | float32 |

Current V0 order:
```text
col 0: mass_in_bucket_kg
col 1: excavated_mass_kg
col 2: mass_in_target_box_kg
col 3: deposited_mass_in_target_box_kg
col 4: min_distance_to_target_m
col 5: target_hard_collision_count
col 6: target_contact_max_normal_force_n
col 7: min_distance_to_dig_area_m
col 8: bucket_depth_below_dig_area_plane_m
col 9: target_horizontal_distance_m
col 10: bucket_height_above_target_rim_m
col 11: bucket_over_target_footprint_mask
col 12: dump_clearance_ok_mask
```

Compatibility note:
- older AGX V0 datasets may still have only the first five columns
- older 7-column datasets may still omit the DigArea fields
- older 9-column datasets omit the explicit target-geometry fields
- Repo A decodes missing collision columns as `0.0`
- Repo A decodes missing DigArea fields as legacy defaults and disables DigArea good-start gating automatically
- Repo A target-safety reward, filtering, and scripted dump guards require
  columns 9 through 12 to exist and `target_horizontal_distance_m >= 0.0`;
  `min_distance_to_target_m` is not used as a fallback
- `target_hard_collision_count` is cumulative within an episode
- `target_contact_max_normal_force_n` is the completed-step maximum monitored force
- `min_distance_to_target_m` is the legacy approximate minimum distance between the current bucket target-distance proxy volume and the active target distance geometry; it is diagnostics-only for target safety
- for `TruckBed`, helper `*FailureVolume` shapes are excluded from target-distance and target hard-collision filtering
- `min_distance_to_dig_area_m` / `bucket_depth_below_dig_area_plane_m` are the DigArea geometry signals used to gate shaped loading reward
- `target_horizontal_distance_m` is the explicit horizontal planar distance between the bucket target-distance proxy footprint and the active target clearance footprint; `0.0` means the footprints overlap and `-1.0` means unavailable
- `bucket_height_above_target_rim_m` is the bucket proxy bottom height relative to the active target clearance volume top/rim
- `bucket_over_target_footprint_mask` and `dump_clearance_ok_mask` are float masks encoded as `0.0` or `1.0`; `dump_clearance_ok_mask` may use target-specific horizontal tolerance and is the source-of-truth clearance mask for target-safety guards, but vertical clearance still requires `bucket_height_above_target_rim_m >= 0.0`

### 5.4 images/fpv

| Property | Value |
| --- | --- |
| Dataset path | `/observations/images/fpv` |
| Shape | `(T, H, W, 3)` |
| dtype | uint8 |
| Channel order | RGB |
| Row order | top-to-bottom |
| V0 transport | raw RGB bytes |

`H` and `W` are runtime-dependent and come from the Unity camera descriptor.

## 6. /action

| Property | Value |
| --- | --- |
| Dataset path | `/action` |
| Shape | `(T, 4)` |
| dtype | float32 |
| Range | normalized `[-1, 1]` after deadzone and scaling |

Column order:
```text
col 0: swing_speed_cmd
col 1: boom_speed_cmd
col 2: stick_speed_cmd
col 3: bucket_speed_cmd
```

These are the exact commands sent through `STEP_REQ`.

Current V0 task scope:
- stationary / fixed-position digging
- no `drive`, `steer`, or track channels in this action dataset yet

## 7. /rewards

| Property | Value |
| --- | --- |
| Dataset path | `/rewards` |
| Shape | `(T,)` |
| dtype | float32 |

Current V0 behavior:
- Repo A stores the testbed-defined AGX excavation mission reward here
- Unity wire `reward` now mirrors
  `deposited_mass_in_target_box_kg` as a backup success proxy, but the saved
  HDF5 reward is still the Repo A mission reward rather than the raw Unity
  wire scalar
- current Repo A ACT behavior-cloning training does not consume `/rewards` as a
  supervised learning target; this dataset is primarily for analysis, replay,
  and eval-side accounting
- Repo A may subtract a fixed hard-collision penalty from the saved mission
  reward when cumulative `target_hard_collision_count` increases on that step
- success remains target-centric and is determined from retained target mass
- legacy V0 recordings often used
  `deposited_mass_in_target_box_kg >= 100.0 kg` for `25` consecutive steps
- current Repo A rerecord baseline commonly uses `dump_complete_final_hold`
  style logic, with thresholds captured in `record_config_yaml` rather than
  hard-coded in the schema contract

## 8. Replay Validity Requirements

A recorded episode is valid iff:
1. replaying `action[t]` through the same backend produces a visually consistent rollout
2. `step_id` is monotonic with no gaps
3. replayed `qpos` stays within a jointly accepted tolerance of recorded `qpos`

The exact `qpos` tolerance is still a team-defined QA threshold and is not
locked here yet.

## 9. Version History

| Version | Notes |
| --- | --- |
| `1.0` | legacy datasets with older observation/image layout |
| `1.1` | adds `timestamps`, `action_source`, `env_state`, `images/fpv`, and new metadata fields; current add-only `env_state` tail columns extend through index 12 |

## 10. Open Items

- Decide whether camera width and height become required metadata or remain
  derivable from the image dataset shape.
- Decide whether Repo B's local JSON/RGB export gets an official conversion
  path into this HDF5 schema.
- The evaluator contract is closed enough for V0 mass-based success, but the
  short written benchmark task definition still needs to be frozen
  (start pose / terrain / rollout packaging).
