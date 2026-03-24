# schema.md — HDF5 Episode Dataset Schema v1.1

Repo: sim-protocol (Repo C - shared)
Last updated: 2026-03-24
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
└── rewards
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
| `param_version` | string | example: `"v0"` |
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
| `operator_id` | string | teleop operator identity |
| `session_id` | string | grouping key |
| `deadzone` | float32[4] | per-axis teleop deadzone |
| `scale` | float32[4] | per-axis teleop scale |
| `limit` | float32[4] | per-axis teleop clip |
| `reset_mode` | string | example: `"baseline_fixed"` |
| `success` | int32/bool | episode-level success label written by Repo A |
| `n_steps` | int32 | convenience metadata |

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
```

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
- success remains target-centric and is determined from retained target mass
- current default success rule is
  `deposited_mass_in_target_box_kg >= 100.0 kg` for `25` consecutive steps

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
| `1.1` | adds `timestamps`, `action_source`, `env_state`, `images/fpv`, and new metadata fields |

## 10. Open Items

- Decide whether camera width and height become required metadata or remain
  derivable from the image dataset shape.
- Decide whether Repo B's local JSON/RGB export gets an official conversion
  path into this HDF5 schema.
- The evaluator contract is closed enough for V0 mass-based success, but the
  short written benchmark task definition still needs to be frozen
  (start pose / terrain / rollout packaging).
