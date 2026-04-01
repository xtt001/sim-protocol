# Windows Platform Switch Checklist (Repo C)

Owner: joint (Unity/AGX team + Python/testbed team)  
Status: shared migration checklist for moving Repo A + Repo B from the current Linux-first workflow to Windows  
Last updated: 2026-04-01

This file is a shared coordination document. It does **not** redefine the
protocol. Its job is to keep the platform migration aligned with the existing
Repo C contract.

If this file conflicts with `protocol.md`, `schema.md`, or `constants.yaml`,
prefer those contract files.

## 1. Goal

Move both:

- Repo A: Python testbed / HDF5 / ACT / eval workflow
- Repo B: Unity + AGX excavator scene and step-ack server

to Windows while keeping the current Repo C shared contract unchanged.

Current motivation:

- Windows is the more realistic future target for PCVR presentation
- the current Linux workflow should be treated as the baseline behavior to
  reproduce first

## 2. Contract Invariants

The following should remain unchanged during the platform switch unless all
three repos jointly agree on a versioned contract update:

- binary framed TCP step-ack transport
- `GET_INFO`, `RESET`, `STEP` message structure
- action dimension and ordering
- `qpos` dimension and ordering
- `qvel` dimension and ordering
- `env_state` dimension and ordering
- HDF5 v1.1 schema
- current target-centric success semantics

In practice, a Windows migration should be treated as an environment migration,
not a protocol redesign.

## 3. Repo C Role During Migration

Repo C remains the shared source of truth for:

- wire protocol
- shared field ordering
- HDF5 schema
- eval suite skeleton

Repo C should change only if:

- a field changes meaning
- a vector changes dimension or ordering
- a required message field is added or removed
- the shared dataset schema changes

Repo C should **not** change merely because Windows uses different drivers,
different file paths, or different runtime packaging.

## 4. Recommended Migration Order

1. Freeze a known-good Linux baseline.
2. Bring up Repo B on Windows first.
3. Validate the Unity step-ack server and scene behavior locally.
4. Bring up Repo A on Windows.
5. Validate live Repo A <-> Repo B interaction over TCP.
6. Only after the desktop workflow is restored, revisit Windows PCVR.

Rationale:

- Repo B is the runtime environment that Repo A depends on for live eval and
  teleop
- getting Unity + AGX + step-ack stable first reduces ambiguity when debugging
  Repo A later

## 5. Pre-Migration Freeze Checklist

- record the current Unity version in use
- record the current AGX/Unity integration version in use
- record the current Python version and conda environment used by Repo A
- save a known-good Linux smoke-test result for:
  - Unity scene launch
  - step-ack smoke test
  - one teleop episode
  - one replay
  - one eval run
- keep a copy of current `protocol.md`, `schema.md`, `constants.yaml`, and
  `eval_suite_v0.yaml` available during migration review

## 6. Repo B Windows Bring-Up Checklist

### 6.1 Copy the correct project root

Copy the full Unity project root, not only the nested Git repo:

- copy the full project corresponding to `/home/pingfan/AGXexcavator`
- do **not** copy only `/home/pingfan/AGXexcavator/Assets/AGXUnity_Excavator`

Reason:

- `ProjectSettings/`
- `Packages/`
- `Assets/XR/`

all matter for runtime behavior, and not all of them live inside Repo B's Git
root.

### 6.2 Recreate the Windows Unity environment

- install Unity `2022.3.62f3`
- install the AGX Unity integration used by the current project
- open the copied Unity project root on Windows
- let Unity reimport the project
- verify that required native plugins load correctly on Windows

### 6.3 Validate the main scene

Open:

- `Assets/AGXUnity_Excavator/AGXUnity_Excavator.unity`

Validate:

- scene compiles cleanly
- excavator scene opens without missing references
- reset works
- target switching works
- `AgxSimStepAckServer` can listen
- FPV capture still works
- current HUD and auxiliary windows behave as expected

### 6.4 VR is not a first-pass blocker

Do not block the Windows migration on HMD availability.

First restore:

- desktop scene rendering
- step-ack server
- teleop compatibility
- eval compatibility

Only after that should Windows PCVR be re-enabled and tested.

## 7. Repo A Windows Bring-Up Checklist

### 7.1 Recreate the Python environment

- install Miniconda or Anaconda on Windows
- recreate the Repo A environment with matching Python and package versions
- verify PyTorch and CUDA compatibility on the target Windows GPU stack
- verify `h5py`, `opencv`, `numpy`, `pyyaml`, and related data dependencies
- install `ffmpeg` in a Windows-visible path if replay/video export depends on it

### 7.2 Validate CLI entry points

Validate that the current Repo A commands still run on Windows:

```bash
python scripts/agx_smoke.py --host <host> --port 5057 --steps 500 --strict
tb-record-teleop --config testbed/configs/teleop_v0.yaml --input joystick --num-episodes 1
tb-replay --episode <episode.hdf5> --config testbed/configs/teleop_v0.yaml --save-video
tb-train --config testbed/configs/act_agx_v0.yaml
tb-eval --config testbed/configs/eval_agx_v0.yaml
```

### 7.3 Check Windows-specific runtime assumptions

- path handling
- temp directories
- shell invocation assumptions
- joystick / HID access
- firewall behavior for TCP clients
- file locking behavior around HDF5 outputs

## 8. Cross-Repo Integration Checklist

### 8.1 Networking

- ensure Repo B listens on a Windows host/port reachable by Repo A
- allow the step-ack TCP port through Windows Firewall
- verify that Repo A points to the correct host IP instead of assuming
  `127.0.0.1` unless both repos run on the same machine

### 8.2 Protocol validation

Before running long experiments, verify:

- `GET_INFO_RESP` is readable by Repo A
- `STEP_RESP.step_id == STEP_REQ.step_id`
- image transport is valid
- `qpos`, `qvel`, and `env_state` lengths match Repo C definitions
- reset semantics remain unchanged

### 8.3 Behavior validation

Run the smallest useful end-to-end sequence:

1. Unity scene running
2. Repo A `agx_smoke.py`
3. one short teleop recording
4. one replay
5. one short eval

Do not start by debugging full ACT training.

## 9. Acceptance Criteria

The Windows migration should be considered successful only when all of the
following are true:

- Repo B main scene runs on Windows
- step-ack smoke test passes
- Repo A can record at least one valid HDF5 episode
- Repo A can replay that episode
- Repo A can run at least one live eval episode against Windows Repo B
- no Repo C contract files needed to change for platform-only reasons

## 10. Common Pitfalls

- copying only the nested Repo B Git directory instead of the full Unity project
- treating a Windows runtime issue as a protocol issue
- trying to enable VR before desktop step-ack is stable
- assuming Linux joystick/device behavior will exactly match Windows
- forgetting Windows Firewall on the step-ack port
- changing vector ordering locally without updating Repo C versioning rules

## 11. Future Windows PCVR Follow-Up

Once the desktop workflow is stable on Windows, the dormant VR spectator path in
Repo B can be revisited.

At that stage, validate separately:

- Windows `OpenXR` provider setup
- SteamVR as active OpenXR runtime
- HMD availability
- spectator camera behavior
- desktop and HMD parallel rendering behavior

This PCVR follow-up should be treated as a separate milestone after the platform
switch, not as part of the minimum migration acceptance bar.
