# AnyMotion

AnyMotion is a reproducible workspace for the pipeline:

`HumanML / MDM text-to-motion -> GMR retargeting -> Unitree G1 motion assets -> BeyondMimic training -> ROS2 real deployment`

This repository does not vendor large upstream codebases, model weights, datasets, or training outputs. Instead, it records:

- the final retargeting configuration used for `HumanML -> G1`
- local code changes as patch files against upstream repositories
- environment setup and validation scripts
- documentation for reproducing the full workflow

## What Is New Here

The main contribution of this project is a **HumanML-specific retargeting path to Unitree G1**.

Upstream GMR mainly targets BVH / SMPL-X / OptiTrack style human motion sources. This project adds a practical adapter for **HumanML / MDM generated 22-joint motion sequences** and makes them usable for G1 whole-body motion tracking.

The core additions are:

1. `HumanML/MDM -> GMR` adapter
   - reads `results.npy` or compatible containers
   - selects one generated sequence by `sample_idx` and `repetition_idx`
   - estimates human height from the generated sequence
   - interpolates the source motion from `20 FPS` to `30 FPS`
   - reconstructs joint transforms in the format expected by GMR

2. `HumanML -> G1` retargeting strategy
   - preserves expressive upper-body motion
   - introduces support-aware lower-body weighting
   - stabilizes pelvis orientation without fully freezing motion
   - adds ground alignment and toe support handling
   - improves wrist and hand tracking so punching motions remain readable

3. `GMR -> BeyondMimic` bridge
   - converts retargeted `pkl` motion into CSV
   - converts CSV into BeyondMimic-compatible NPZ
   - supports replay, policy training, and ONNX export

4. `BeyondMimic -> ROS2 real deployment` fixes
   - local launch utility replacement
   - controller config fixes
   - runtime DDS library path fix for `motion_tracking_controller real.launch.py`

## Repository Layout

```text
.
├── configs/
│   └── gmr/
│       └── humanml_to_g1_final.json
├── docs/
│   ├── GMR调参.md
│   └── GMR添加新机器人.md
├── patches/
│   ├── gmr.patch
│   ├── motion_tracking_controller.patch
│   └── whole_body_tracking.patch
├── scripts/
│   ├── bootstrap_sources.sh
│   ├── check_beyondmimic_isaaclab210.py
│   └── setup_beyondmimic_isaaclab210.sh
└── sources.lock.yaml
```

## Upstream Dependencies

This project depends on the following upstream repositories and commits:

- `GMR`: `bb1bbe40774794fceb2a7c579a3464a28e68c844`
- `whole_body_tracking`: `cd65172032893724b445448818c34165846d847d`
- `motion_tracking_controller`: `cbdb4a80d5ea506b2045bdd39cdfb4058084aeb4`
- `unitree_bringup`: `1b2c83dd846e92eee5b070e9551b6845257b0785`
- `motion-diffusion-model`: `ef8edce6a53c6ab19e53b4d4dcf15bc0bc60a778`
- `HumanML3D`: `9176e8fb446b71c7d2a725eb5cf6fec1ae3b3c23`

The lock file is stored in [sources.lock.yaml](./sources.lock.yaml).

## Reconstructing The Workspace

Clone this repository, then reconstruct upstream sources:

```bash
git clone <this_repo_url>
cd AnyMotion
bash scripts/bootstrap_sources.sh
```

This will:

- clone all required upstream repositories into `src/`
- checkout the exact commits recorded in `sources.lock.yaml`
- apply the local patches from `patches/`

## Environment Setup

### 1. BeyondMimic / Isaac Lab 2.1.0

The recommended stack for `whole_body_tracking` in this project is:

- Python `3.10`
- Isaac Sim `4.5.0.0`
- Isaac Lab `v2.1.0`

Setup:

```bash
bash scripts/setup_beyondmimic_isaaclab210.sh
```

Validate:

```bash
python scripts/check_beyondmimic_isaaclab210.py
```

The setup script is parameterized through environment variables such as:

- `PUBLIC_ROOT`
- `ENV_PREFIX`
- `ISAACLAB_DIR`
- `WHOLE_BODY_TRACKING_DIR`
- `CONDA_BASE`

Heavy downloads and caches are intentionally redirected outside the repository.

### 2. ROS2 Real Deployment

This project was validated on:

- Ubuntu `22.04`
- ROS2 `Humble`
- fish shell for daily use

The real deployment side depends on:

- `motion_tracking_controller`
- `unitree_bringup`
- `unitree_systems`
- correct DDS runtime libraries for `UnitreeSdk2`

The relevant runtime launch fix is preserved in `patches/motion_tracking_controller.patch`.

## HumanML To G1 Strategy

The final configuration is stored at:

- [configs/gmr/humanml_to_g1_final.json](./configs/gmr/humanml_to_g1_final.json)

This config is the most important artifact in the repository. It encodes the final retargeting behavior for generated HumanML motions on Unitree G1.

### Design Goals

The target behavior was:

- keep the **upper body expressive**, especially for boxing-like arm motion
- avoid **pelvis yaw collapse** when one leg swings backward
- reduce **lower-limb twisting** caused by directly matching noisy or stylized generated leg poses
- keep the robot closer to the ground during support phases
- maintain usable toe orientation and wrist participation

### Key Sections In The Config

#### 1. `human_root_heading_lock`

This section stabilizes the robot pelvis heading.

- `enabled: true`
- `mode: "initial"`
- `strength: 1.0`

Interpretation:

- the pelvis heading is biased toward the initial facing direction
- this prevents the whole lower body from rotating just to satisfy a stylized leg pose
- it is especially important for boxing motions where the generated human may fake stepping without reliable support contacts

#### 2. `joint_damping_priors`

This section adds soft constraints to the waist:

- `waist_yaw_joint`
- `waist_roll_joint`
- `waist_pitch_joint`

Interpretation:

- the waist is **not hard-locked**
- instead, it becomes more resistant during strong support phases
- this suppresses sim-looking over-rotation while preserving some natural torso motion

This was more effective than a pure hard lock because a full waist lock improved stability but made the motion too stiff.

#### 3. `adaptive_leg_task_weighting`

This is the core lower-body stabilization mechanism.

It uses:

- foot and toe contact bodies
- support score blending
- stance/swing-dependent task scaling

Interpretation:

- when a leg is likely in stance, its foot and leg targets stay important
- when a leg is likely in swing, its positional target is softened
- this prevents the solver from sacrificing pelvis orientation just to force an airborne leg into an extreme pose

This is the main reason the final boxing motion became much more stable than the earlier static-weight versions.

#### 4. `adaptive_ground_alignment`

This section introduces a soft ground projection step.

Interpretation:

- support feet are used to estimate a reference ground contact height
- the root is adjusted within a bounded range
- both feet remain visually closer to the ground

This helps reduce the “both feet floating” effect often seen when a generated motion is transferred directly from HumanML to a humanoid robot.

#### 5. `human_scale_table`

This scales HumanML body segments before IK matching.

Interpretation:

- pelvis and spine retain most of the human scale
- legs are slightly shortened to better fit G1 proportions
- arms are scaled down more aggressively to fit G1 reach and shoulder geometry

This scaling is necessary because HumanML body proportions and G1 link lengths are not directly compatible.

#### 6. `ik_match_table2`

This is the actual human-joint to robot-link mapping table.

Examples:

- `pelvis <- Hips`
- `torso_link <- Spine2`
- `left_hip_yaw_link <- LeftUpLeg`
- `left_knee_link <- LeftLeg`
- `left_ankle_roll_link <- LeftFootMod`
- `left_toe_link <- LeftToe`
- `left_shoulder_yaw_link <- LeftArm`
- `left_elbow_link <- LeftForeArm`
- `left_wrist_yaw_link <- LeftHand`

Each entry provides:

- the matched human joint
- positional cost
- rotational cost
- local translation offset
- local quaternion offset

The quaternion offsets are critical because HumanML joint frames do not align with G1 link frames by default.

## Full Pipeline

### 1. Generate Human Motion With MDM

Run generation in `motion-diffusion-model` and obtain a `results.npy`.

This repository does not ship model weights or generated motion outputs.

### 2. Retarget HumanML Motion To G1 With GMR

After reconstructing `src/GMR`:

```bash
cd src/GMR
python scripts/humanml_to_robot.py \
  --motion_file <path_to_results.npy> \
  --robot unitree_g1 \
  --sample_idx 0 \
  --repetition_idx 0 \
  --ik_config /path/to/AnyMotion/configs/gmr/humanml_to_g1_final.json \
  --save_path retargeting_data/output.pkl \
  --rate_limit
```

Notes:

- `results.npy` usually contains multiple generated sequences
- `sample_idx` and `repetition_idx` select one sequence
- the adapter estimates height automatically
- source motion is upsampled from `20 FPS` to `30 FPS`

### 3. Convert GMR Output To BeyondMimic Input

Within `src/whole_body_tracking` after patch application:

```bash
python scripts/gmr_pkl_to_csv.py \
  --input_file /path/to/output.pkl \
  --output_file /path/to/output.csv
```

Then:

```bash
python scripts/csv_to_npz.py \
  --input_file /path/to/output.csv \
  --output_file /path/to/output.npz \
  --input_fps 30 \
  --no_wandb \
  --headless
```

### 4. Replay In Isaac Sim

```bash
python scripts/replay_npz.py \
  --motion_file /path/to/output.npz
```

### 5. Train Tracking Policy

```bash
python scripts/rsl_rl/train.py \
  --task=Tracking-Flat-G1-v0 \
  --motion_file /path/to/output.npz \
  --headless \
  --logger wandb \
  --log_project_name boxing_tracking \
  --run_name g1_boxing_seq10
```

### 6. Export / Play Policy

```bash
python scripts/rsl_rl/play.py \
  --task=Tracking-Flat-G1-v0 \
  --num_envs=2 \
  --motion_file /path/to/output.npz \
  --load_run <run_name>
```

### 7. ROS2 Real Deployment

After reconstructing `src/colcon_ws/src/motion_tracking_controller` and `src/colcon_ws/src/unitree_bringup`, and after sourcing ROS2:

```bash
ros2 launch motion_tracking_controller real.launch.py \
  robot_type:=g1 \
  network_interface:=<your_ethernet_interface> \
  policy_path:=<path_to_exported_policy.onnx> \
  start_step:=0 \
  ext_pos_corr:=false \
  rosbag_storage_id:=sqlite3
```

## Important Notes

### What Is Intentionally Not Included

This repository intentionally does **not** include:

- MDM checkpoints
- HumanML datasets
- generated `results.npy`
- retargeted `pkl/csv/npz` motion outputs
- BeyondMimic training checkpoints
- exported ONNX policies
- WandB logs
- rosbags
- large third-party assets

These are either too large, reproducible from upstream sources, or unsuitable for a clean public repository.

### About Patches

The patch files in `patches/` are the authoritative record of local code changes.

- `patches/gmr.patch`: HumanML adapter and G1 retargeting logic
- `patches/whole_body_tracking.patch`: CSV/NPZ bridge, replay, training and playback fixes
- `patches/motion_tracking_controller.patch`: MuJoCo and real-launch deployment fixes

If you need to inspect the actual source-level modifications, start there.

## Documentation

The repository keeps two markdown documents from the development process:

- [docs/GMR调参.md](./docs/GMR调参.md)
- [docs/GMR添加新机器人.md](./docs/GMR添加新机器人.md)

Bundled PDFs and large reference files are intentionally excluded from version control.

## License And Upstream Ownership

This repository contains patch files and small helper scripts around upstream projects. The original source code remains owned by the respective upstream repositories and their licenses.
