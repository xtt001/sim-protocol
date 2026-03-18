# sim-protocol — Shared Protocol & Schema (Repo C)

**Owner:** joint (Unity/AGX team + Python/testbed team)  
**Rule:** This repo is the **single source of truth** for all inter-team contracts.  
Do not duplicate or override these definitions in Repo A or Repo B.

---

## What this repo contains

| File | Purpose |
|---|---|
| [protocol.md](protocol.md) | Full binary wire protocol spec (V0): header, message types, STEP_REQ/RESP field layout, step-ack contract, versioning rules |
| [schema.md](schema.md) | HDF5 episode dataset schema v1.1: all datasets, shapes, dtypes, column orderings, add-only policy |
| [constants.yaml](constants.yaml) | Single source of truth for all numeric constants: MSG_TYPES, vector dims, action/qpos/qvel ordering, env_state indices, success thresholds, camera params |
| [eval_suite_v0.yaml](eval_suite_v0.yaml) | Fixed evaluation suite: scenarios, seeds, reset flags, success rule parameters |

---

## Quick reference (most important locked constants)

### Action vector (length 4, `[-1, 1]`)
```
index 0: swing_speed_cmd
index 1: boom_speed_cmd
index 2: stick_speed_cmd
index 3: bucket_speed_cmd
```

### qpos (length 3, `[0, 1]`)
```
index 0: boom_position_norm
index 1: stick_position_norm
index 2: bucket_position_norm
```

### qvel (length 4, physical units)
```
index 0: swing_speed
index 1: boom_speed
index 2: stick_speed
index 3: bucket_speed
```

### env_state (length ≥ 1)
```
index 0: mass_in_bucket
```

### Success rule (spec §8)
```
success if mass_in_bucket >= 1.0  for 25 consecutive steps  (0.5s @ 50Hz)
```

### Step-ack hard rule
```
STEP_RESP.step_id must equal STEP_REQ.step_id — no exceptions.
```

---

## Version bump policy

| What changed | Action required |
|---|---|
| New optional JSON field in GET_INFO_RESP | No bump needed |
| New optional HDF5 dataset | Increment `schema_version` attribute |
| New *required* HDF5 dataset | Increment `schema_version` + announce to both teams |
| New message type | Bump `protocol.version` + joint review |
| Change vector ordering or dims | Bump `protocol.version` + `schema_version` + joint review |
| Remove any field | **NOT ALLOWED** without deprecation cycle |

---

## How to use constants.yaml

**Python (Repo A):**
```python
import yaml
C = yaml.safe_load(open("constants.yaml"))
ACTION_DIM  = C["action"]["dim"]         # 4
QPOS_ORDER  = C["qpos"]["order"]         # {0: "boom_position_norm", ...}
MASS_THRESH = C["success"]["mass_thresh"] # 1.0
```

**C# (Repo B):**  
Parse with YamlDotNet, or hardcode the same values and keep this file as the
written reference that both sides agree on.

---

## TODOs (fill in once Unity team confirms)

- [ ] Confirm `camera_width` × `camera_height` (currently 320×240 placeholder)
- [ ] Confirm `mass_in_bucket` units and appropriate `mass_thresh` value
- [ ] Confirm `qvel` physical unit scale (raw AGX constraint speed?)
- [ ] Confirm whether `camera_fps` will always match `control_hz` or can differ
