#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="${SOURCE_ROOT:-$REPO_ROOT/src}"

clone_or_update() {
    local url="$1"
    local commit="$2"
    local target="$3"

    mkdir -p "$(dirname "$target")"
    if [[ ! -d "$target/.git" ]]; then
        git clone "$url" "$target"
    fi

    git -C "$target" fetch --all --tags
    git -C "$target" checkout "$commit"
}

apply_patch_if_needed() {
    local target="$1"
    local patch_file="$2"

    if [[ ! -f "$patch_file" ]]; then
        return 0
    fi

    if git -C "$target" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
        echo "[INFO] Patch already applied: $patch_file"
        return 0
    fi

    git -C "$target" apply "$patch_file"
    echo "[INFO] Applied patch: $patch_file"
}

clone_or_update "https://github.com/YanjieZe/GMR.git" \
    "bb1bbe40774794fceb2a7c579a3464a28e68c844" \
    "$SOURCE_ROOT/GMR"
clone_or_update "https://github.com/HybridRobotics/whole_body_tracking.git" \
    "cd65172032893724b445448818c34165846d847d" \
    "$SOURCE_ROOT/whole_body_tracking"
clone_or_update "https://github.com/HybridRobotics/motion_tracking_controller.git" \
    "cbdb4a80d5ea506b2045bdd39cdfb4058084aeb4" \
    "$SOURCE_ROOT/colcon_ws/src/motion_tracking_controller"
clone_or_update "https://github.com/qiayuanl/unitree_bringup.git" \
    "1b2c83dd846e92eee5b070e9551b6845257b0785" \
    "$SOURCE_ROOT/colcon_ws/src/unitree_bringup"
clone_or_update "https://github.com/guytevet/motion-diffusion-model.git" \
    "ef8edce6a53c6ab19e53b4d4dcf15bc0bc60a778" \
    "$SOURCE_ROOT/motion-diffusion-model"
clone_or_update "https://github.com/EricGuo5513/HumanML3D.git" \
    "9176e8fb446b71c7d2a725eb5cf6fec1ae3b3c23" \
    "$SOURCE_ROOT/HumanML3D"

apply_patch_if_needed "$SOURCE_ROOT/GMR" "$REPO_ROOT/patches/gmr.patch"
apply_patch_if_needed "$SOURCE_ROOT/whole_body_tracking" "$REPO_ROOT/patches/whole_body_tracking.patch"
apply_patch_if_needed "$SOURCE_ROOT/colcon_ws/src/motion_tracking_controller" "$REPO_ROOT/patches/motion_tracking_controller.patch"

echo "[INFO] Workspace sources are ready under $SOURCE_ROOT"
