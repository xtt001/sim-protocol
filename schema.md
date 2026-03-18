# schema.md — HDF5 Episode Dataset Schema v1.1

**Repo:** sim-protocol (Repo C — shared)  
**Last updated:** 2026-03-18  
**Owner:** joint (Unity/AGX team + Python/testbed team)  
**Rule:** **Add-only.** Never remove or rename existing datasets/groups. Increment `schema_version` when any new *required* field is introduced.

---

## 1) File layout

```
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

---

## 2) /metadata (HDF5 attributes on the root group)

### Required (v1.1)

| Attribute | Type | Value / Example |
|---|---|---|
| `schema_version` | str | `"1.1"` |
| `task_name` | str | `"agx_excavation_teleop"` |
| `sim_backend` | str | `"agxunity"` |
| `seed` | int32 | `-1` (unused in V0) |
| `param_version` | str | `"v0"` |
| `timestamp` | str | ISO 8601, e.g. `"2026-03-18T14:00:00"` |
| `control_hz` | int32 | `50` |
| `dt` | float32 | `0.02` |
| `action_semantics` | str | `"actuator_speed_cmd"` |
| `camera_names` | str[] / JSON str | `["fpv"]` |
| `camera_width` | int32 | e.g. `320` |
| `camera_height` | int32 | e.g. `240` |
| `image_format` | str | `"raw_rgb"` (V0); `"h264"` (V1+) |

### Optional / recommended

| Attribute | Type | Notes |
|---|---|---|
| `operator_id` | str | who drove |
| `session_id` | str | grouping key |
| `deadzone` | float32[4] | per-axis deadzone values |
| `scale` | float32[4] | per-axis speed scale |
| `limit` | float32[4] | per-axis hard clip |
| `protocol_version` | int32 | from GET_INFO_RESP |
| `reset_mode` | str | `"baseline_fixed"` (V0) |

---

## 3) /timestamps (required)

| Dataset | Shape | dtype | Notes |
|---|---|---|---|
| `step_id` | `(T,)` | int64 | monotonically increasing; matches STEP_RESP.step_id |
| `step_ns` | `(T,)` | int64 | wall-clock ns at record time (optional but recommended) |

---

## 4) /action_source (required)

Records *who or what* generated each action.

| Dataset | Shape | dtype | Values |
|---|---|---|---|
| `type` | `(T,)` | str (variable-length) | `"teleop"` \| `"policy"` \| `"scripted"` |
| `id`   | `(T,)` | str (variable-length) | `"joystick"` \| `"keyboard"` \| `"policy:act@ckpt_path"` |

Optional:

| Dataset | Shape | dtype | Notes |
|---|---|---|---|
| `latency_ms` | `(T,)` | float32 | action generation latency |

---

## 5) /observations (required)

### 5.1 qpos — joint positions

| Property | Value |
|---|---|
| Dataset path | `/observations/qpos` |
| Shape | `(T, 3)` |
| dtype | float32 |
| Range | [0, 1] (normalized) |

**Column ordering (LOCKED, V0):**
```
col 0: boom_position_norm   (from BoomPrismatics[0])
col 1: stick_position_norm
col 2: bucket_position_norm
```

Note: swing_position_norm is **not available in V0** (omitted entirely).

### 5.2 qvel — actuator speeds

| Property | Value |
|---|---|
| Dataset path | `/observations/qvel` |
| Shape | `(T, 4)` |
| dtype | float32 |
| Units | physical units (not normalized) |

**Column ordering (LOCKED, V0):**
```
col 0: swing_speed
col 1: boom_speed    (from BoomPrismatics[0])
col 2: stick_speed
col 3: bucket_speed
```

### 5.3 env_state — environment signals

| Property | Value |
|---|---|
| Dataset path | `/observations/env_state` |
| Shape | `(T, M)` |
| dtype | float32 |

**Column ordering (V0, M=1):**
```
col 0: mass_in_bucket   (units: see constants.yaml)
```

Additional columns may be appended in future versions. Do not rely on M being fixed.

### 5.4 images/fpv — first-person camera

| Property | Value |
|---|---|
| Dataset path | `/observations/images/fpv` |
| Shape | `(T, H, W, 3)` |
| dtype | uint8 |
| Channel order | RGB |
| V0 source | raw RGB from RenderTexture |

Future: `/observations/images/fpv_h264` will store variable-length encoded bytes + an index table if H.264 transport is adopted. The `fpv` dataset will remain for backward compatibility.

---

## 6) /action (required)

| Property | Value |
|---|---|
| Dataset path | `/action` |
| Shape | `(T, 4)` |
| dtype | float32 |
| Range | [-1, 1] (normalized, post-deadzone, post-scale) |

**Column ordering (LOCKED, V0):**
```
col 0: swing_speed_cmd
col 1: boom_speed_cmd
col 2: stick_speed_cmd
col 3: bucket_speed_cmd
```

These are the **post-deadzone, post-scale** commands exactly as sent via STEP_REQ. Replay must produce identical AGX behavior.

---

## 7) /rewards (optional but recommended)

| Property | Value |
|---|---|
| Dataset path | `/rewards` |
| Shape | `(T,)` |
| dtype | float32 |

V0: set to `0.0` — success is computed by the evaluator from `env_state`.

---

## 8) /labels (optional, future)

Reserved for future use:

| Dataset | dtype | Notes |
|---|---|---|
| `success` | bool | computed after eval |
| `fail_code` | str | reason for failure |
| `phase` | str | e.g. `"dig"`, `"lift"`, `"dump"` |

---

## 9) Replay validity requirement

A dataset episode is **valid** iff:
1. Replaying `action[t]` through the same backend step-by-step produces a visually consistent rollout.
2. Replayed `qpos` stays within tolerance of recorded `qpos`:
   - mean absolute error per joint < 0.05 (to be finalized once hardware variance is measured)
3. `step_id` sequence is monotonically increasing with no gaps.

---

## 10) Version history

| Version | Date | Changes |
|---|---|---|
| 1.0 | (legacy) | qpos, qvel, images/top, action, rewards, metadata |
| 1.1 | 2026-03-18 | + timestamps/step_id, timestamps/step_ns, action_source/type, action_source/id, observations/env_state, observations/images/fpv, metadata: control_hz, dt, action_semantics, camera_names, image_format |

---

## 11) Add-only policy

- Append new datasets/groups freely.
- **Never rename or remove** existing datasets.
- Increment `schema_version` for any new *required* field.
- Old readers must not crash when encountering unknown datasets (read them as `None` / skip).
