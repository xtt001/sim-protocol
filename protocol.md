# protocol.md — AGXUnity ↔ Python Testbed Wire Protocol (V0)

**Repo:** sim-protocol (Repo C — shared)  
**Last updated:** 2026-03-18  
**Owner:** joint (Unity/AGX team + Python/testbed team)  
**Rule:** Any change to message types, field ordering, or dimensions requires a version bump + joint PR review.

---

## 0) Locked Decisions (Do NOT change without joint review)

| # | Decision |
|---|---|
| 1 | Simulator = **AGXUnity (Unity/C#)** |
| 2 | Communication = **custom C# TCP socket** (NOT ROS-TCP) |
| 3 | Stepping = **strict step-ack** using **manual DoStep()** |
| 4 | Vision = **first-person camera ("fpv") required** |
| 5 | Image transport V0 = **raw RGB**; V1 = H.264 (optional) |
| 6 | Action semantics = **actuator/constraint speed cmd** (`actuator_speed_cmd`) |
| 7 | qpos (len=3) = boom/stick/bucket position_norm; **no swing_position_norm in V0** |
| 8 | qvel (len=4) = swing/boom/stick/bucket speeds |
| 9 | boom signals use **BoomPrismatics[0] only** in V0 |

---

## 1) Why Step-Ack

Python sends `STEP_REQ(step_id=k)`. Unity must reply `STEP_RESP(step_id=k)` — same k, same step.

Required because:
- training data validity (action/obs must be aligned)
- episode replay must reproduce the exact same trajectory
- eval suite reproducibility (fair model comparison)

Unity `FixedUpdate` can run multiple fixed steps per rendered frame (catch-up). Step-ack bypasses this ambiguity.

---

## 2) Transport

- TCP, binary framing, little-endian
- Every message = **16-byte header** + **payload** (0 or more bytes)
- Python is the **client**; Unity is the **server**

---

## 3) Header (16 bytes, little-endian)

```
offset  size  type     field
──────  ────  ───────  ─────────────────────────────────────────
0       4     uint32   magic        = 0xA6A6A6A6
4       2     uint16   version      = 1
6       2     uint16   msg_type     (see §4)
8       4     uint32   payload_len  (bytes after this header)
12      4     uint32   crc32        (0 = not checked in V0)
```

C# struct layout:
```csharp
[StructLayout(LayoutKind.Sequential, Pack = 1)]
struct MsgHeader {
    uint magic;       // 0xA6A6A6A6
    ushort version;   // 1
    ushort msg_type;
    uint payload_len;
    uint crc32;
}
```

---

## 4) Message Types

| Name | uint16 value | Direction |
|---|---|---|
| `GET_INFO_REQ`  | 1 | Python → Unity |
| `GET_INFO_RESP` | 2 | Unity → Python |
| `RESET_REQ`     | 3 | Python → Unity |
| `RESET_RESP`    | 4 | Unity → Python |
| `STEP_REQ`      | 5 | Python → Unity |
| `STEP_RESP`     | 6 | Unity → Python |

---

## 5) GET_INFO (capability handshake)

### 5.1 GET_INFO_REQ
- `payload_len = 0` (empty body)

### 5.2 GET_INFO_RESP
- `payload_len = N` (UTF-8 JSON string, N bytes)

Minimum required JSON fields:
```json
{
  "protocol_version": 1,
  "dt": 0.02,
  "control_hz": 50,
  "action_semantics": "actuator_speed_cmd",
  "action_dim": 4,
  "action_order": ["swing_speed_cmd", "boom_speed_cmd", "stick_speed_cmd", "bucket_speed_cmd"],
  "qpos_dim": 3,
  "qpos_order": ["boom_position_norm", "stick_position_norm", "bucket_position_norm"],
  "qvel_dim": 4,
  "qvel_order": ["swing_speed", "boom_speed", "stick_speed", "bucket_speed"],
  "cameras": ["fpv"],
  "camera_width": 320,
  "camera_height": 240,
  "camera_fps": 50,
  "image_format": "raw_rgb",
  "env_state_dim": 1,
  "env_state_layout": {"mass_in_bucket": 0}
}
```

---

## 6) RESET

### 6.1 RESET_REQ (12 + N bytes)

```
offset  size  type     field
──────  ────  ───────  ──────────────────────────────
0       4     int32    seed               (-1 = unused)
4       1     uint8    reset_terrain      (1 = yes)
5       1     uint8    reset_pose         (1 = yes)
6       2     uint8[2] _pad
8       4     uint32   scenario_id_len    (N, 0 if none)
12      N     char[]   scenario_id        (UTF-8, no null terminator)
```

Python struct format: `"<iBBxxI"` + variable-length string

### 6.2 RESET_RESP (16 bytes)

```
offset  size  type     field
──────  ────  ───────  ──────────────────────────────
0       1     uint8    success            (1 = ok, 0 = failed)
1       3     uint8[3] _pad
4       4     float32  dt                 (confirms timestep)
8       4     float32  control_hz         (confirms rate)
12      4     uint32   warning_flags      (0 = none)
```

Python struct format: `"<BxxxffI"`

---

## 7) STEP (primary loop)

### 7.1 STEP_REQ (32 bytes)

```
offset  size  type     field
──────  ────  ───────  ──────────────────────────────────────────
0       8     int64    step_id            (monotonically increasing)
8       16    float32  action[4]          (swing, boom, stick, bucket speed cmd)
                                          normalized in [-1, 1]
24      8     int64    client_time_ns     (0 = unused; for latency profiling)
```

Python struct format: `"<qffffq"`  Total: 32 bytes

Action vector order (LOCKED):
```
index 0: swing_speed_cmd
index 1: boom_speed_cmd
index 2: stick_speed_cmd
index 3: bucket_speed_cmd
```

### 7.2 STEP_RESP (variable, minimum 60 + M*4 + 20 bytes)

**Fixed part 1 — state (40 bytes):**
```
offset  size  type     field
──────  ────  ───────  ──────────────────────────────────────────
0       8     int64    step_id            (MUST equal STEP_REQ.step_id)
8       12    float32  qpos[3]            (boom, stick, bucket position_norm)
20      16    float32  qvel[4]            (swing, boom, stick, bucket speed)
36      4     uint32   env_state_len      (M, number of float32 values)
```

Python struct format: `"<qfffffffI"`  Total: 40 bytes

**Variable part — env_state (M × 4 bytes):**
```
float32  env_state[M]   (index 0 = mass_in_bucket)
```

**Fixed part 2 — image header (20 bytes):**
```
offset  size  type     field
──────  ────  ───────  ──────────────────────────────────────────
0       4     float32  reward             (0.0 in V0; computed in Python)
4       1     uint8    image_format       (ImageFormat enum: 0=NONE, 1=RAW_RGB, 2=H264)
5       3     uint8[3] _pad
8       4     int32    image_w
12      4     int32    image_h
16      4     uint32   image_payload_len  (K bytes)
```

Python struct format: `"<fBxxxiiI"`  Total: 20 bytes

**Variable part — image bytes (K bytes):**
```
uint8[K]  image_payload  (raw RGB: K = image_w * image_h * 3)
```

---

## 8) ImageFormat enum

| Name | uint8 value |
|---|---|
| `NONE`    | 0 |
| `RAW_RGB` | 1 |
| `H264`    | 2 |

V0 must use `RAW_RGB`. H264 is reserved for V1.

---

## 9) Step-Ack Hard Contract

1. Python sends exactly one `STEP_REQ` and blocks.
2. Unity calls `DoStep()` exactly once (N internal substeps are allowed, but **exposed as 1 step externally**).
3. Unity sends exactly one `STEP_RESP` with **the same `step_id`**.
4. Python's `client.step()` **raises `ProtocolError`** if `STEP_RESP.step_id != STEP_REQ.step_id`.
5. `step_id` must be monotonically increasing per connection. Start at 0 on each RESET.

---

## 10) State vector ordering (LOCKED, V0)

### qpos (length 3, float32, range [0, 1])
```
index 0: boom_position_norm   (from BoomPrismatics[0])
index 1: stick_position_norm
index 2: bucket_position_norm
```

### qvel (length 4, float32, physical units)
```
index 0: swing_speed
index 1: boom_speed           (from BoomPrismatics[0])
index 2: stick_speed
index 3: bucket_speed
```

### env_state (length M, float32)
```
index 0: mass_in_bucket       (see constants.yaml for units/threshold)
```

---

## 11) Versioning Rules

| Change | Required action |
|---|---|
| Add optional JSON field to GET_INFO_RESP | No version bump needed |
| Add new message type | Bump `version` (header field) + joint review |
| Change vector ordering or dimension | Bump `version` + joint review + schema version bump |
| Change image format flag semantics | Bump `version` + joint review |
| Remove a field | **NOT ALLOWED without deprecation cycle** |

Current version: **1**
