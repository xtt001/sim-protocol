# protocol.md — AGXUnity <-> Python Step-Ack Wire Protocol

Repo: sim-protocol (Repo C - shared)
Last updated: 2026-04-24
Owner: joint (Unity/AGX team + Python/testbed team)

This document is aligned to the current Repo B implementation.
If older drafts in Repo A or Repo B disagree with this file, those older drafts
are stale.

## 1. Scope

The protocol is used for:
- `GET_INFO`
- `RESET`
- `STEP`

It is a TCP binary protocol with:
- fixed-size frame header
- binary payloads
- CRC32 over payload bytes
- raw RGB image transport for V0

Current control semantics:
- action semantics: `actuator_speed_cmd`
- action order: `[swing_speed_cmd, boom_speed_cmd, stick_speed_cmd, bucket_speed_cmd]`
- V0 task scope is fixed-position / stationary digging; `drive`, `steer`, and
  track motion are intentionally excluded from the current wire action space
- Repo B baseline consumes pending requests on `Update`
- transport-branch scheduling experiments are outside the baseline wire
  contract documented here

Current observation semantics:
- qpos order: `[swing_position_norm, boom_position_norm, stick_position_norm, bucket_position_norm]`
- qvel order: `[swing_speed, boom_speed, stick_speed, bucket_speed]`
- env_state order:
  `[mass_in_bucket_kg, excavated_mass_kg, mass_in_target_box_kg, deposited_mass_in_target_box_kg, min_distance_to_target_m, target_hard_collision_count, target_contact_max_normal_force_n, min_distance_to_dig_area_m, bucket_depth_below_dig_area_plane_m, target_horizontal_distance_m, bucket_height_above_target_rim_m, bucket_over_target_footprint_mask, dump_clearance_ok_mask, bucket_dump_area_relative_x_m, bucket_dump_area_relative_z_m, bucket_dump_area_footprint_outside_distance_m]`

`mass_in_target_box_kg` semantics:
- this field always refers to the currently active dump target selected by Unity
- current E85 scenes use dump-area targets

`deposited_mass_in_target_box_kg` semantics:
- this field is reset-relative net retained mass inside the active target
- Unity computes it as current measured target mass minus the reset baseline,
  clamped to zero

`min_distance_to_target_m` semantics:
- this legacy field is the approximate minimum distance between the bucket
  target-distance proxy volume and the currently active target distance
  geometry
- it is retained for diagnostics and historical comparability only
- Repo A target-safety reward, data filtering, and scripted dump guards must
  not use it as a fallback for explicit target geometry
- in the current Unity scene that bucket proxy volume is editor-configurable
  on `ExcavationMassTracker`
- the target side now prefers target hard box shapes and only falls back to a
  dedicated target-distance volume when those shapes are unavailable
- `-1.0` means the distance could not be evaluated

`target_horizontal_distance_m` semantics:
- this field is the explicit horizontal planar distance between the bucket
  target-distance proxy footprint and the active target clearance footprint
- `0.0` means the bucket and target footprints overlap in the target
  horizontal plane
- `-1.0` means the explicit target geometry could not be evaluated

`bucket_height_above_target_rim_m` semantics:
- this field is the bucket target-distance proxy bottom height relative to the
  active target clearance volume top/rim
- positive values mean the proxy bottom is above the rim
- negative values mean the proxy bottom is below the rim

`bucket_over_target_footprint_mask` semantics:
- this field is a float mask
- `1.0` means the bucket target-distance proxy footprint overlaps the active
  target clearance footprint
- `0.0` means it is outside or unavailable

`dump_clearance_ok_mask` semantics:
- this field is a float mask
- `1.0` means the bucket is within the active target's dump-clearance
  horizontal tolerance and `bucket_height_above_target_rim_m >= 0.0`
- active dump areas may use a wider horizontal tolerance than strict footprint
  overlap; vertical clearance is not tolerant
- `0.0` means dump clearance is not currently satisfied or the explicit
  geometry is unavailable

`bucket_dump_area_relative_x_m` / `bucket_dump_area_relative_z_m` semantics:
- signed bucket proxy center coordinates in the active dump-area local frame
- planners use these fields when they need a local approach corridor rather
  than unsigned footprint proximity alone

`bucket_dump_area_footprint_outside_distance_m` semantics:
- unsigned horizontal distance from the bucket proxy footprint to the active
  dump-area footprint
- `0.0` means the footprint overlaps or is inside

`min_distance_to_dig_area_m` semantics:
- this field is the approximate minimum distance between the bucket measurement
  volume and the scene `DigArea` thin box
- `0.0` means the bucket measurement volume is touching or overlapping the
  DigArea box volume
- `-1.0` means the distance could not be evaluated

`bucket_depth_below_dig_area_plane_m` semantics:
- this field is the current bucket depth below the DigArea plane
- Unity computes it as `max(0, dig_plane_y - bucket_world_min_y)`
- it only becomes positive when the bucket measurement volume goes below the
  DigArea plane

`target_hard_collision_count` semantics:
- this field is the cumulative episode count of hard-collision occurrences against the currently active target
- Unity increments it only when a new continuous excavator-vs-target contact session reaches the hard-collision threshold
- while the excavator remains in continuous contact with the target, the count does not continue increasing every frame
- after the excavator leaves the target, the next qualifying touch can increment the count again
- the current Unity scene default threshold is `hard_collision_normal_force_thresh_n = 5000.0`
- source shapes are the enabled AGX `Collide.Shape` components under the excavator root
- target shapes come from the currently active target hard-surface shape set
- the monitored target hard-surface set covers the active dump-area target geometry

`target_contact_max_normal_force_n` semantics:
- this field is the maximum monitored solved normal-force magnitude, in Newtons, observed during the completed step across excavator-vs-active-target contacts
- `0.0` means no monitored active-target contact was observed for that step

## 2. Byte Order and Primitive Encoding

All numeric values use .NET `BinaryWriter` / `BinaryReader` style encoding:
- little-endian integers
- little-endian IEEE754 `float32`

Primitive encodings:
- `bool` -> `uint8` (`0` or `1`)
- `string` -> `int32 byte_len` + UTF-8 bytes
- `float[]` -> `int32 len` + `len * float32`
- `string[]` -> `int32 len` + repeated encoded strings
- `bytes` -> `int32 byte_len` + raw bytes

## 3. Frame Header

Every TCP message is:
- `header[16 bytes]`
- `payload[payload_len bytes]`

Header layout:

| Field | Type | Value / Meaning |
| --- | --- | --- |
| `magic` | `uint32` | `0xA6A6A6A6` |
| `version` | `uint16` | `1` |
| `msg_type` | `uint16` | see section 4 |
| `payload_len` | `uint32` | payload byte length |
| `crc32` | `uint32` | CRC32 of payload only |

CRC32 details:
- polynomial: `0xEDB88320`
- initial value: `0xFFFFFFFF`
- final xor: `0xFFFFFFFF`

Current behavior:
- frames with wrong magic must be rejected
- frames with wrong header version must be rejected
- frames with excessive payload size must be rejected
- frames with invalid CRC32 must be rejected

## 4. Message Types

| Name | Numeric value |
| --- | --- |
| `GET_INFO_REQ` | `1` |
| `GET_INFO_RESP` | `2` |
| `RESET_REQ` | `3` |
| `RESET_RESP` | `4` |
| `STEP_REQ` | `5` |
| `STEP_RESP` | `6` |

## 5. Request Payloads

### 5.1 GET_INFO_REQ

Payload:
- empty payload allowed

### 5.2 RESET_REQ

Binary field order:
1. `seed: int32`
2. `reset_terrain: bool`
3. `reset_pose: bool`
4. `client_time_ns: int64` optional
5. `scenario_id: string` optional

Notes:
- zero-length payload may be accepted and treated as defaults
- optional trailing fields may be omitted
- phase-1 `scenario_id` may route to a Repo B preset that overrides
  `reset_terrain` / `reset_pose` and applies a post-reset target switch
- unknown `scenario_id` values should degrade to warnings, not protocol failure
- phase-1 does not define pose-offset or DigArea-offset semantics for `scenario_id`

### 5.3 STEP_REQ

Binary field order:
1. `step_id: int64`
2. `action: float32[]`
3. `client_time_ns: int64` optional

Constraints:
- action length must be at least `4`
- Unity currently consumes the first four action values in this order:
  `[swing, boom, stick, bucket]`

## 6. Common Response Prefix

All response payloads start with:
1. `success: bool`
2. `error: string`

If `success == 0`, the rest of the payload is still emitted in normal layout,
but only the prefix and warnings should be trusted.

## 7. GET_INFO_RESP Payload

After the common response prefix, fields are written in this order:
1. `protocol_version: string`
2. `dt: float32`
3. `control_hz: float32`
4. `action_semantics: string`
5. `action_order: string[]`
6. `qpos_order: string[]`
7. `qvel_order: string[]`
8. `env_state_order: string[]`
9. `camera_names: string[]`
10. `supports_reset_pose: bool`
11. `supports_images: bool`
12. `cameras: camera_descriptor[]`
13. `warnings: string[]`

`camera_descriptor` field order:
1. `name: string`
2. `width: int32`
3. `height: int32`
4. `fps: float32`
5. `pixel_format: string`
6. `row_order: string`

Current known values:
- `protocol_version = "agx-sim/v0"`
- `action_semantics = "actuator_speed_cmd"`
- `camera_names = ["fpv"]` when the FPV camera is configured
- `supports_reset_pose = true`
- `supports_images = true` when the FPV camera is configured
- `pixel_format = "raw_rgb"`
- `row_order = "top_to_bottom"`

Important note:
- camera width, height, and fps are runtime-advertised by the running Unity
  camera and should not be treated as fixed global constants yet

## 8. RESET_RESP Payload

After the common response prefix, fields are written in this order:
1. `reset_applied: bool`
2. `dt: float32`
3. `control_hz: float32`
4. `warnings: string[]`

Current behavior:
- `reset_applied = true` when `reset_terrain || reset_pose`
- when `reset_pose = true` and `reset_terrain = false`, Unity resets pose and
  counters without forcing a terrain height reset
- when both flags are true, Unity performs the full scene reset path,
  including dump-area target state when present
- when `reset_terrain = true`, Unity rebuilds the deformable terrain state so
  dynamic soil mass/particles are cleared as part of reset, including particles
  that were still trapped in the bucket
- for step-ack serving, a successful reset also re-arms the machine controller
  engine so subsequent `STEP_REQ` actions take effect immediately
- the current reset path prefers the current Unity scene reset service and only
  falls back to the episode reset path for full resets
- when Unity serving is configured to disable `EpisodeManager`, local HUD
  release-controls UI is not part of the shared wire contract and should not be
  relied on by clients
- terrain reset is handled by Unity `ResetTerrain` / `SceneResetService`; the
  excavation metrics component no longer mutates terrain heights during reset
- baseline step-ack requests are consumed on Unity `Update`
- transport-branch scheduling experiments are outside the baseline payload
  contract documented here

## 9. STEP_RESP Payload

After the common response prefix, fields are written in this order:
1. `step_id: int64`
2. `qpos: float32[]`
3. `qvel: float32[]`
4. `env_state: float32[]`
5. `image_format: string`
6. `image_w: int32`
7. `image_h: int32`
8. `image_payload: bytes`
9. `reward: float32`
10. `sim_time_ns: int64`
11. `warnings: string[]`

Current known values:
- `qpos.len = 4`
- `qvel.len = 4`
- `env_state.len = 16`
- `reward = deposited_mass_in_target_box_kg`
- `image_format = "raw_rgb"` when FPV capture succeeds
- `image_w = 0`, `image_h = 0`, `image_payload = empty` when no FPV frame is available
- FPV capture renders from the tracked camera only; Unity IMGUI overlays such
  as HUD text or camera-window chrome are not part of `image_payload`

Current evaluator note:
- success for V0 is not decided by this `reward` field
- Unity currently mirrors the main retained-target-mass success signal into
  `reward` as a backup wire field:
  `reward = deposited_mass_in_target_box_kg`
- Repo A currently computes AGX excavation mission reward locally from
  `env_state`
- Repo A's AGX evaluator currently decides success from `task_success` /
  retained target mass hold, not from `highest_reward == max_reward`
- clients should still prefer `env_state[3]` /
  `deposited_mass_in_target_box_kg` as the source-of-truth named signal
- current testbed reward sub-targets are:
  - qualified DigArea good start plus meaningful bucket load acquisition
  - approaching the active target while loaded
  - increasing retained mass inside the active target
  - holding retained target mass above the configured success threshold
- Repo A also applies a fixed per-step hard-collision penalty when the
  cumulative `target_hard_collision_count` increases on that step
- Repo A target-safety reward, data filtering, and scripted dump guards require
  `env_state[9]` through `env_state[15]` to be present and
  `target_horizontal_distance_m >= 0.0`; `env_state[4]` is not a fallback
- when `env_state[7]` and `env_state[8]` are present, Repo A only opens the
  shaped loading reward after bucket load increase occurs while touching the
  DigArea region and going below the DigArea plane
- current default success rule is:
  `deposited_mass_in_target_box_kg >= 100.0 kg` for `25` consecutive steps

Current target-routing note:
- `env_state[2]` and `env_state[3]` report the currently active target selected
  by Unity runtime target routing
- `env_state[4]` reports approximate minimum bucket-to-target distance in meters
- `env_state[5]` reports cumulative episode hard-collision count
- `env_state[6]` reports the completed-step maximum monitored contact normal force in Newtons
- `env_state[7]` reports the approximate minimum bucket-to-DigArea distance in meters
- `env_state[8]` reports the current bucket depth below the DigArea plane in meters
- `env_state[9]` reports explicit horizontal bucket-to-target clearance-footprint distance in meters
- `env_state[10]` reports bucket bottom height above the active target rim in meters
- `env_state[11]` reports whether the bucket proxy footprint overlaps the active target footprint
- `env_state[12]` reports whether target dump clearance is currently satisfied
- `env_state[13]` reports bucket proxy center x in the active dump-area local frame
- `env_state[14]` reports bucket proxy center z in the active dump-area local frame
- `env_state[15]` reports unsigned horizontal distance outside the active dump-area footprint
- target identity itself is currently scene/runtime configuration and is not
  carried explicitly in the binary `STEP_RESP` payload

Image payload rules:
- layout is row-major
- row order is top-to-bottom
- channel order is RGB
- byte count should be `image_w * image_h * 3`

## 10. Locked V0 Ordering

### Action
```text
[swing_speed_cmd, boom_speed_cmd, stick_speed_cmd, bucket_speed_cmd]
```

### qpos
```text
[swing_position_norm, boom_position_norm, stick_position_norm, bucket_position_norm]
```

### qvel
```text
[swing_speed, boom_speed, stick_speed, bucket_speed]
```

### env_state
```text
[
  mass_in_bucket_kg,
  excavated_mass_kg,
  mass_in_target_box_kg,
  deposited_mass_in_target_box_kg,
  min_distance_to_target_m,
  target_hard_collision_count,
  target_contact_max_normal_force_n,
  min_distance_to_dig_area_m,
  bucket_depth_below_dig_area_plane_m,
  target_horizontal_distance_m,
  bucket_height_above_target_rim_m,
  bucket_over_target_footprint_mask,
  dump_clearance_ok_mask,
  bucket_dump_area_relative_x_m,
  bucket_dump_area_relative_z_m,
  bucket_dump_area_footprint_outside_distance_m
]
```

## 11. Step-Ack Rules

Required control loop:
1. Python sends `STEP_REQ(step_id=k, action=...)`
2. Unity applies the action
3. Unity performs exactly one logical `DoStep()`
4. Unity samples qpos, qvel, env_state, and FPV frame
5. Unity returns `STEP_RESP(step_id=k, ...)`

Hard rules:
- `STEP_RESP.step_id` must equal the request `step_id`
- one `STEP_REQ` corresponds to one exposed simulation step
- image payload must describe the same post-step state as qpos, qvel, and env_state

## 12. Current Implementation Update

Compared with older drafts, the current implementation has these important updates:
- JSON transport has been removed; transport is now binary framed TCP
- `qpos` has been expanded from 3D to 4D by adding `swing_position_norm`
- FPV export uses raw RGB bytes, not JSON-wrapped image data
- `GET_INFO_RESP` advertises camera metadata from the running FPV camera
- `reset_pose` is supported through the current reset path
- active-target hard-collision summary metrics are now exported without changing
  the meaning of the first five env_state indices
- Unity now also exports DigArea good-start geometry metrics while keeping the
  first seven env_state indices stable
- Unity now also exports explicit target dump geometry metrics while keeping
  the first nine env_state indices stable; Repo A requires these fields for
  target-safety training and scripted dump guards, with no fallback to
  `min_distance_to_target_m`
- the target-distance field now uses the editor-configurable bucket proxy
  volume on `ExcavationMassTracker`

## 13. Known Limits

- `protocol_version` string is still `agx-sim/v0`
- boom position and speed still use `BoomPrismatics[0]`
- `swing_position_norm` exists, but its normalization window is scene/config dependent
- transport is still a single-client sequential TCP service; the server now
  drops stale dead clients, but there is no higher-level reconnect/session
  protocol above TCP
- there is still no full contact-event stream on the wire; only the current
  active-target hard-collision summary metrics are exported

## 14. Versioning

- Header `version = 1` is the wire-header version
- Current logical protocol string is `agx-sim/v0`
- Changing required field layout, vector ordering, or dimensions requires a
  joint version bump and review
