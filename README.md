# sim-protocol — Shared Protocol and Schema (Repo C)

Owner: joint (Unity/AGX team + Python/testbed team)
Rule: this repo is the shared contract surface for Repo A and Repo B.

Current status:
- Repo C has been updated to match the current Repo B binary step-ack protocol.
- Anything still uncertain in Repo B is marked provisional here instead of being
  guessed or frozen as a fake constant.

## Contents

| File | Purpose |
| --- | --- |
| [protocol.md](protocol.md) | Wire protocol for `GET_INFO`, `RESET`, `STEP` |
| [schema.md](schema.md) | HDF5 episode schema v1.1 |
| [constants.yaml](constants.yaml) | Shared constants and ordering definitions |
| [eval_suite_v0.yaml](eval_suite_v0.yaml) | Fixed eval suite skeleton for AGX excavation |

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
```

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

Operational mapping:
- `tb-record-teleop --config testbed/configs/teleop_v0.yaml --input joystick --num-episodes 5`
  is the current canonical Repo A data-collection command
- `tb-train --config testbed/configs/act_agx_v0.yaml` is offline and consumes
  only Repo A HDF5 episodes
- `tb-eval --config testbed/configs/eval_agx_v0.yaml` is live and requires the
  Unity step-ack server to be running

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
- Pending step-ack requests are consumed on Unity `FixedUpdate`, keeping live
  step-ack teleop aligned with the advertised fixed simulation timestep.
- V0 success is `mass_in_bucket_kg >= 2.0` at any point within the
  `500`-step episode.
- `reward` is currently a placeholder `0.0`; success is computed post-hoc from
  the recorded `env_state` series.

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
| New required wire field | Bump protocol version and review jointly |
| Change vector ordering or dimension | Bump protocol version and schema version |
| New required HDF5 field | Bump schema version |
| Remove an existing field | Not allowed without deprecation plan |

## Open Follow-Up

- Replace placeholder GitHub handles in `CODEOWNERS`.
- Wire Repo A to consume Repo C definitions instead of only mirroring Repo B.
- Decide whether Repo B's local JSON/RGB episode export should get an official
  conversion utility into the shared HDF5 schema.
- Revisit the fixed `2.0 kg` success threshold only if the Unity scene/material
  calibration changes materially.
- Freeze a short written V0 benchmark task spec for start pose / terrain /
  episode packaging, since the control and evaluator contracts are now ahead of
  the task-sheet wording.
