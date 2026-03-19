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

## What Is Settled

- Transport is binary framed TCP, not JSON.
- Header size is 16 bytes with CRC32 over payload bytes.
- `GET_INFO_RESP` is a binary field sequence with string arrays and camera
  descriptors.
- `qpos` is currently 4D in the running Unity implementation.
- FPV transport is raw RGB in V0.
- Action semantics are `actuator_speed_cmd`.

## What Is Still Provisional

- The exact semantic range for `swing_position_norm` is not a hard physical
  limit. It depends on the configured Unity normalization window.
- `mass_thresh_kg` for success is still joint-team TBD.
- FPV width, height, and fps are runtime-advertised by `GET_INFO_RESP`; they
  should not be treated as globally fixed constants yet.
- Boom position/speed still comes from `BoomPrismatics[0]` in the current
  Unity implementation.

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
- Revisit success thresholds and camera metadata once Repo B calibration is final.
