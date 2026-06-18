# AnyMotion

AnyMotion 是一个可复现的工作区，用于打通以下完整流程：

`HumanML / MDM 文本生成动作 -> GMR 动作重定向 -> Unitree G1 机器人动作资产 -> BeyondMimic 策略训练 -> ROS2 真机部署`

本仓库**不直接内置**大型上游代码库、模型权重、数据集或训练产物，而是只保留以下关键内容：

- `HumanML -> G1` 使用的最终重定向配置
- 针对上游仓库的本地代码改动补丁
- 环境安装与校验脚本
- 用于复现完整流程的文档

## 本项目的新增内容

本项目最主要的贡献是：**面向 HumanML 的 Unitree G1 专用重定向路径**。

上游 GMR 主要面向 BVH / SMPL-X / OptiTrack 这类人体动作源，而本项目新增了一套可实际使用的适配层，使 **HumanML / MDM 生成的 22 关节人体动作序列** 可以直接用于 G1 的全身动作跟踪与重定向。

核心新增点包括：

1. `HumanML/MDM -> GMR` 适配器
   - 读取 `results.npy` 或兼容格式容器
   - 使用 `sample_idx` 和 `repetition_idx` 选择具体生成序列
   - 从生成序列中估计人体身高
   - 将源动作从 `20 FPS` 插值到 `30 FPS`
   - 重建 GMR 所需的人体关节变换格式

2. `HumanML -> G1` 重定向策略
   - 保留更有表现力的上半身动作
   - 为下肢引入支撑感知的自适应权重
   - 在不完全冻结动作的情况下稳定骨盆朝向
   - 增加地面对齐与脚趾支撑处理
   - 修复手腕/手部跟踪，使拳击动作上肢更自然

3. `GMR -> BeyondMimic` 数据桥接
   - 将重定向得到的 `pkl` 动作转换为 CSV
   - 将 CSV 再转换为 BeyondMimic 可用的 NPZ
   - 支持回放、策略训练和 ONNX 导出

4. `BeyondMimic -> ROS2 真机部署` 修复
   - 本地化 launch 工具替换
   - 控制器配置修复
   - 为 `motion_tracking_controller real.launch.py` 修复 DDS 动态库运行时路径

## 仓库结构

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

## 上游依赖

本项目依赖以下上游仓库及固定提交版本：

- `GMR`: `bb1bbe40774794fceb2a7c579a3464a28e68c844`
- `whole_body_tracking`: `cd65172032893724b445448818c34165846d847d`
- `motion_tracking_controller`: `cbdb4a80d5ea506b2045bdd39cdfb4058084aeb4`
- `unitree_bringup`: `1b2c83dd846e92eee5b070e9551b6845257b0785`
- `motion-diffusion-model`: `ef8edce6a53c6ab19e53b4d4dcf15bc0bc60a778`
- `HumanML3D`: `9176e8fb446b71c7d2a725eb5cf6fec1ae3b3c23`

版本锁定文件位于 [sources.lock.yaml](./sources.lock.yaml)。

## 重建工作区

先克隆本仓库，再自动拉取并重建上游源码：

```bash
git clone <this_repo_url>
cd AnyMotion
bash scripts/bootstrap_sources.sh
```

该脚本会执行：

- 将所需上游仓库全部克隆到 `src/`
- checkout 到 `sources.lock.yaml` 中记录的精确 commit
- 应用 `patches/` 中保存的本地修改补丁

## 环境配置

### 1. BeyondMimic / Isaac Lab 2.1.0

本项目中 `whole_body_tracking` 推荐使用的环境组合为：

- Python `3.10`
- Isaac Sim `4.5.0.0`
- Isaac Lab `v2.1.0`

安装：

```bash
bash scripts/setup_beyondmimic_isaaclab210.sh
```

校验：

```bash
python scripts/check_beyondmimic_isaaclab210.py
```

安装脚本支持通过以下环境变量进行参数化：

- `PUBLIC_ROOT`
- `ENV_PREFIX`
- `ISAACLAB_DIR`
- `WHOLE_BODY_TRACKING_DIR`
- `CONDA_BASE`

所有大体积下载与缓存默认都被重定向到仓库外部。

### 2. ROS2 真机部署

本项目验证环境为：

- Ubuntu `22.04`
- ROS2 `Humble`
- 日常操作 shell 为 `fish`

真机部署侧依赖：

- `motion_tracking_controller`
- `unitree_bringup`
- `unitree_systems`
- 与 `UnitreeSdk2` 匹配的正确 DDS 运行时动态库

相关修复已经保存在 `patches/motion_tracking_controller.patch` 中。

## HumanML 到 G1 的重定向策略

最终配置文件位于：

- [configs/gmr/humanml_to_g1_final.json](./configs/gmr/humanml_to_g1_final.json)

这是本仓库中最重要的成果文件之一。它定义了生成式 HumanML 动作在 Unitree G1 上的最终重定向行为。

### 设计目标

这套策略的目标是：

- 尽可能保留**有表现力的上半身动作**，尤其是拳击类动作
- 避免在单腿后摆时出现**骨盆偏航崩塌**
- 降低直接拟合风格化腿部姿态所造成的**下肢扭转**
- 让机器人在支撑阶段更贴近地面
- 保持脚趾方向与手腕参与度，避免动作“木”

### 配置中的关键模块

#### 1. `human_root_heading_lock`

这一部分用于稳定机器人骨盆朝向。

- `enabled: true`
- `mode: "initial"`
- `strength: 1.0`

含义：

- 骨盆朝向会被轻度约束到初始正面方向
- 这样可以避免求解器为了对齐某条摆动腿，而让整个下半身整体旋转
- 对拳击类动作尤其重要，因为生成动作中的“迈步”很多时候并不具备真实可靠的支撑接触信息

#### 2. `joint_damping_priors`

这一部分对腰部关节加入软约束：

- `waist_yaw_joint`
- `waist_roll_joint`
- `waist_pitch_joint`

含义：

- 腰部并不是被**硬锁定**
- 而是在支撑更稳定时自动增大阻尼/代价
- 这样可以压制仿真中不自然的过度扭腰，同时保留一定的躯干自然动作

相比纯粹的硬锁腰，这种方式更平衡：完全锁死确实更稳，但动作会明显变僵。

#### 3. `adaptive_leg_task_weighting`

这是下半身稳定化的核心机制。

它综合利用：

- 脚掌与脚趾接触体
- 支撑得分混合
- 支撑相 / 摆动相的不同任务缩放

含义：

- 当某条腿更像支撑腿时，它的脚和腿部目标会保持较高权重
- 当某条腿更像摆动腿时，它的位置目标会被适当放松
- 这样可以避免求解器为了强行拟合一条离地腿，而牺牲骨盆与整体下肢稳定性

这是最终拳击动作相比早期静态权重方案更稳定的主要原因。

#### 4. `adaptive_ground_alignment`

这一部分引入了柔性的地面对齐机制。

含义：

- 使用支撑脚估计参考落地点高度
- 对 root 高度做有界调整
- 使双脚在视觉上更接近地面

它可以明显减弱“两个脚都悬空”的问题，这是 HumanML 直接迁移到类人机器人上时很常见的现象。

#### 5. `human_scale_table`

这一部分在 IK 匹配前对 HumanML 各身体段进行缩放。

含义：

- 骨盆和躯干保留较多原始人体比例
- 腿部略缩短，以更接近 G1 的腿长比例
- 手臂缩放更明显，以适配 G1 的肩部与臂长范围

这是必要的，因为 HumanML 的人体比例与 G1 的真实连杆长度并不天然匹配。

#### 6. `ik_match_table2`

这是人体关节到机器人连杆的实际映射表。

例如：

- `pelvis <- Hips`
- `torso_link <- Spine2`
- `left_hip_yaw_link <- LeftUpLeg`
- `left_knee_link <- LeftLeg`
- `left_ankle_roll_link <- LeftFootMod`
- `left_toe_link <- LeftToe`
- `left_shoulder_yaw_link <- LeftArm`
- `left_elbow_link <- LeftForeArm`
- `left_wrist_yaw_link <- LeftHand`

每个映射项都包含：

- 对应的人体关节
- 位置代价
- 旋转代价
- 局部平移偏移
- 局部四元数偏移

其中四元数偏移非常关键，因为 HumanML 的关节局部坐标系与 G1 连杆坐标系默认并不一致。

## 完整流程

### 1. 使用 MDM 生成人体动作

在 `motion-diffusion-model` 中完成动作生成，得到一个 `results.npy`。

本仓库**不提供**模型权重或生成结果文件。

### 2. 使用 GMR 将 HumanML 动作重定向到 G1

在重建好的 `src/GMR` 中执行：

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

说明：

- `results.npy` 往往包含多个生成序列
- `sample_idx` 和 `repetition_idx` 用于选出其中一条
- 适配器会自动估计人体身高
- 源动作会从 `20 FPS` 自动插值到 `30 FPS`

### 3. 将 GMR 输出转换为 BeyondMimic 输入

在应用补丁后的 `src/whole_body_tracking` 中执行：

```bash
python scripts/gmr_pkl_to_csv.py \
  --input_file /path/to/output.pkl \
  --output_file /path/to/output.csv
```

然后：

```bash
python scripts/csv_to_npz.py \
  --input_file /path/to/output.csv \
  --output_file /path/to/output.npz \
  --input_fps 30 \
  --no_wandb \
  --headless
```

### 4. 在 Isaac Sim 中回放

```bash
python scripts/replay_npz.py \
  --motion_file /path/to/output.npz
```

### 5. 训练跟踪策略

```bash
python scripts/rsl_rl/train.py \
  --task=Tracking-Flat-G1-v0 \
  --motion_file /path/to/output.npz \
  --headless \
  --logger wandb \
  --log_project_name boxing_tracking \
  --run_name g1_boxing_seq10
```

### 6. 导出 / 回放策略

```bash
python scripts/rsl_rl/play.py \
  --task=Tracking-Flat-G1-v0 \
  --num_envs=2 \
  --motion_file /path/to/output.npz \
  --load_run <run_name>
```

### 7. ROS2 真机部署

在重建 `src/colcon_ws/src/motion_tracking_controller` 与 `src/colcon_ws/src/unitree_bringup`，并完成 ROS2 环境 source 后执行：

```bash
ros2 launch motion_tracking_controller real.launch.py \
  robot_type:=g1 \
  network_interface:=<your_ethernet_interface> \
  policy_path:=<path_to_exported_policy.onnx> \
  start_step:=0 \
  ext_pos_corr:=false \
  rosbag_storage_id:=sqlite3
```

## 重要说明

### 本仓库刻意不包含的内容

本仓库**不会**提交以下内容：

- MDM checkpoint
- HumanML 数据集
- 生成得到的 `results.npy`
- 重定向生成的 `pkl/csv/npz` 动作文件
- BeyondMimic 训练 checkpoint
- 导出的 ONNX 策略
- WandB 日志
- rosbag
- 大型第三方资产

原因是这些内容要么体积过大，要么可从上游复现，要么不适合放入公开、干净的源码仓库。

### 关于补丁

`patches/` 目录中的补丁文件，是本项目本地源码改动的权威记录。

- `patches/gmr.patch`: HumanML 适配层与 G1 重定向逻辑
- `patches/whole_body_tracking.patch`: CSV/NPZ 桥接、回放、训练与播放修复
- `patches/motion_tracking_controller.patch`: MuJoCo 与真机部署修复

如果你想查看实际源码修改，建议优先从这些补丁开始。

## 文档

本仓库保留了开发过程中整理的两篇 Markdown 文档：

- [docs/GMR调参.md](./docs/GMR调参.md)
- [docs/GMR添加新机器人.md](./docs/GMR添加新机器人.md)

PDF 参考资料和大体积文档被刻意排除在版本控制之外。

## 许可证与上游归属

本仓库主要包含补丁文件、配置与辅助脚本。原始源码归属于对应上游仓库，并遵循各自的许可证。
