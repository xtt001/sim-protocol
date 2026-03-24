# protocol.md — AGXUnity <-> Python Step-Ack Wire Protocol

Repo: sim-protocol (Repo C - shared)
Last updated: 2026-03-24
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

Current observation semantics:
- qpos order: `[swing_position_norm, boom_position_norm, stick_position_norm, bucket_position_norm]`
- qvel order: `[swing_speed, boom_speed, stick_speed, bucket_speed]`
- env_state order:
  `[mass_in_bucket_kg, excavated_mass_kg, mass_in_target_box_kg, deposited_mass_in_target_box_kg, min_distance_to_target_m]`

`mass_in_target_box_kg` semantics:
- this field always refers to the currently active dump target selected by Unity
- current main-scene targets are `ContainerBox` and `TruckBed`

`deposited_mass_in_target_box_kg` semantics:
- this field is reset-relative net retained mass inside the active target
- Unity computes it as current measured target mass minus the reset baseline,
  clamped to zero

`min_distance_to_target_m` semantics:
- this field is the approximate minimum distance between the bucket measurement
  volume and the currently active target measurement volume
- it is distance-based, not collision-based
- `-1.0` means the distance could not be evaluated

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
- when both flags are true, Unity performs the full scene reset path
- when `reset_terrain = true`, Unity rebuilds the deformable terrain state so
  dynamic soil mass/particles are cleared as part of reset, including particles
  that were still trapped in the bucket
- for step-ack serving, a successful reset also re-arms the machine controller
  engine so subsequent `STEP_REQ` actions take effect immediately
- the current reset path prefers the current Unity scene reset service and only
  falls back to the episode reset path for full resets
- terrain reset is handled by Unity `ResetTerrain` / `SceneResetService`; the
  excavation metrics component no longer mutates terrain heights during reset
- pending step-ack requests are consumed on Unity `FixedUpdate`, so live
  step-ack teleop stays aligned with the fixed simulation timestep

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
- `env_state.len = 5`
- `reward = 0.0`
- `image_format = "raw_rgb"` when FPV capture succeeds
- `image_w = 0`, `image_h = 0`, `image_payload = empty` when no FPV frame is available

Current evaluator note:
- success for V0 is not decided by this `reward` field
- Repo A currently computes AGX excavation mission reward locally from
  `env_state`
- current testbed reward sub-targets are:
  - meaningful bucket load acquisition
  - approaching the active target while loaded
  - increasing retained mass inside the active target
  - holding retained target mass above the configured success threshold
- current default success rule is:
  `deposited_mass_in_target_box_kg >= 100.0 kg` for `25` consecutive steps

Current target-routing note:
- `env_state[2]` and `env_state[3]` report the currently active target selected
  by Unity runtime target routing
- `env_state[4]` reports approximate minimum bucket-to-target distance in meters
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
  min_distance_to_target_m
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

## 13. Known Limits

- `protocol_version` string is still `agx-sim/v0`
- boom position and speed still use `BoomPrismatics[0]`
- `swing_position_norm` exists, but its normalization window is scene/config dependent
- transport is still a single-client sequential TCP service; the server now
  drops stale dead clients, but there is no higher-level reconnect/session
  protocol above TCP

## 14. Versioning

- Header `version = 1` is the wire-header version
- Current logical protocol string is `agx-sim/v0`
- Changing required field layout, vector ordering, or dimensions requires a
  joint version bump and review
