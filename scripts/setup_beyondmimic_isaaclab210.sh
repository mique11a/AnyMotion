#!/usr/bin/env bash
set -euo pipefail

# Install a clean BeyondMimic stack that matches the repository requirements:
# - Python 3.10
# - Isaac Sim 4.5.0
# - Isaac Lab v2.1.0
# - whole_body_tracking editable package
#
# All heavy downloads, caches, and environments are redirected into PUBLIC_ROOT.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBLIC_ROOT="${PUBLIC_ROOT:-$HOME/public_resources}"
ENV_PREFIX="${ENV_PREFIX:-$PUBLIC_ROOT/envs/beyondmimic_il210}"
ISAACLAB_DIR="${ISAACLAB_DIR:-$PUBLIC_ROOT/src/IsaacLab-2.1.0}"
WHOLE_BODY_TRACKING_DIR="${WHOLE_BODY_TRACKING_DIR:-$PWD/src/whole_body_tracking}"
CONDA_PKGS_DIRS="${CONDA_PKGS_DIRS:-$PUBLIC_ROOT/conda-pkgs}"
PIP_CACHE_DIR="${PIP_CACHE_DIR:-$PUBLIC_ROOT/pip-cache}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$PUBLIC_ROOT/xdg-cache}"
TMPDIR="${TMPDIR:-$PUBLIC_ROOT/tmp}"
WHEELHOUSE_DIR="${WHEELHOUSE_DIR:-$PUBLIC_ROOT/wheelhouse}"
ISAACSIM_VERSION="${ISAACSIM_VERSION:-4.5.0.0}"
INSTALL_EXTSCACHE="${INSTALL_EXTSCACHE:-0}"
CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"

mkdir -p "$PUBLIC_ROOT/src" "$CONDA_PKGS_DIRS" "$PIP_CACHE_DIR" "$XDG_CACHE_HOME" "$TMPDIR" "$WHEELHOUSE_DIR"

export CONDA_PKGS_DIRS
export PIP_CACHE_DIR
export XDG_CACHE_HOME
export TMPDIR
export OMNI_KIT_ACCEPT_EULA=YES
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_DEFAULT_TIMEOUT="${PIP_DEFAULT_TIMEOUT:-120}"
export PIP_RETRIES="${PIP_RETRIES:-20}"
export PIP_RESUME_RETRIES="${PIP_RESUME_RETRIES:-20}"

if [[ ! -f "$CONDA_BASE/etc/profile.d/conda.sh" ]]; then
    echo "Missing conda initialization script: $CONDA_BASE/etc/profile.d/conda.sh" >&2
    exit 1
fi

source "$CONDA_BASE/etc/profile.d/conda.sh"

pip_install() {
    python -m pip install \
        --retries "$PIP_RETRIES" \
        --resume-retries "$PIP_RESUME_RETRIES" \
        --timeout "$PIP_DEFAULT_TIMEOUT" \
        "$@"
}

resolve_nvidia_wheel_url() {
    local package_name="$1"
    local wheel_name="$2"
    python - "$package_name" "$wheel_name" <<'PY'
import re
import sys
import urllib.request

package_name = sys.argv[1]
wheel_name = sys.argv[2]
index_url = f"https://pypi.nvidia.com/{package_name}/"
with urllib.request.urlopen(index_url, timeout=60) as response:
    html = response.read().decode("utf-8", errors="replace")

match = re.search(rf'href="([^"#]*{re.escape(wheel_name)}(?:#[^"]*)?)"', html)
if not match:
    raise SystemExit(f"Failed to find {wheel_name} on {index_url}")

href = match.group(1).split("#", 1)[0]
if href.startswith("http://") or href.startswith("https://"):
    print(href)
else:
    print(index_url + href)
PY
}

download_wheel_with_resume() {
    local package_name="$1"
    local wheel_name="$2"
    local output_path="$WHEELHOUSE_DIR/$wheel_name"

    if [[ -f "$output_path" ]]; then
        echo "Using cached wheel: $output_path"
        return 0
    fi

    local wheel_url
    wheel_url="$(resolve_nvidia_wheel_url "$package_name" "$wheel_name")"
    echo "Downloading $wheel_name to $output_path"

    if command -v aria2c >/dev/null 2>&1; then
        aria2c \
            --continue=true \
            --max-tries=20 \
            --retry-wait=5 \
            --timeout=120 \
            --split=8 \
            --max-connection-per-server=8 \
            --min-split-size=16M \
            --dir "$WHEELHOUSE_DIR" \
            --out "$wheel_name" \
            "$wheel_url"
    elif command -v wget >/dev/null 2>&1; then
        wget \
            --continue \
            --tries=20 \
            --timeout=120 \
            --directory-prefix="$WHEELHOUSE_DIR" \
            --output-document="$output_path" \
            "$wheel_url"
    else
        curl \
            --location \
            --continue-at - \
            --retry 20 \
            --retry-delay 5 \
            --connect-timeout 30 \
            --max-time 0 \
            --output "$output_path" \
            "$wheel_url"
    fi
}

install_extscache() {
    local wheel_names=(
        "isaacsim_extscache_kit-$ISAACSIM_VERSION-cp310-none-manylinux_2_34_x86_64.whl"
        "isaacsim_extscache_kit_sdk-$ISAACSIM_VERSION-cp310-none-manylinux_2_34_x86_64.whl"
        "isaacsim_extscache_physics-$ISAACSIM_VERSION-cp310-none-manylinux_2_34_x86_64.whl"
    )
    local package_names=(
        "isaacsim-extscache-kit"
        "isaacsim-extscache-kit-sdk"
        "isaacsim-extscache-physics"
    )

    local i
    for ((i = 0; i < ${#package_names[@]}; ++i)); do
        download_wheel_with_resume "${package_names[i]}" "${wheel_names[i]}"
    done

    pip_install \
        --no-index \
        --find-links "$WHEELHOUSE_DIR" \
        "isaacsim-extscache-kit==$ISAACSIM_VERSION" \
        "isaacsim-extscache-kit-sdk==$ISAACSIM_VERSION" \
        "isaacsim-extscache-physics==$ISAACSIM_VERSION"
}

if [[ ! -d "$ENV_PREFIX" ]]; then
    conda create -y -p "$ENV_PREFIX" python=3.10
fi

conda activate "$ENV_PREFIX"

python -m pip install --upgrade pip

# Isaac Lab v2.1.0 docs recommend a CUDA-enabled PyTorch 2.5.1 build for CUDA 12 systems.
pip_install \
    torch==2.5.1 \
    torchvision==0.20.1 \
    --index-url https://download.pytorch.org/whl/cu121

pip_install \
    "isaacsim[all]==$ISAACSIM_VERSION" \
    --extra-index-url https://pypi.nvidia.com

if [[ "$INSTALL_EXTSCACHE" == "1" ]]; then
    install_extscache
else
    echo "Skipping isaacsim extscache wheels (INSTALL_EXTSCACHE=$INSTALL_EXTSCACHE)."
    echo "This avoids 2GB+ cache wheel downloads during setup."
    echo "If you want pre-cached extensions later, rerun with INSTALL_EXTSCACHE=1."
fi

if [[ ! -d "$ISAACLAB_DIR" ]]; then
    git clone --branch v2.1.0 --depth 1 https://github.com/isaac-sim/IsaacLab.git "$ISAACLAB_DIR"
else
    git -C "$ISAACLAB_DIR" fetch --tags
    git -C "$ISAACLAB_DIR" checkout v2.1.0
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is missing. Install it first, e.g. sudo apt install cmake build-essential" >&2
    exit 1
fi

pushd "$ISAACLAB_DIR" >/dev/null
pip_install -e "${ISAACLAB_DIR}/source/isaaclab"
pip_install -e "${ISAACLAB_DIR}/source/isaaclab_assets"
pip_install -e "${ISAACLAB_DIR}/source/isaaclab_tasks"
./isaaclab.sh --install rsl_rl
popd >/dev/null

if [[ ! -d "$WHOLE_BODY_TRACKING_DIR" ]]; then
    echo "whole_body_tracking repository not found: $WHOLE_BODY_TRACKING_DIR" >&2
    exit 1
fi

UNITREE_ASSET_DIR="$WHOLE_BODY_TRACKING_DIR/source/whole_body_tracking/whole_body_tracking/assets/unitree_description"
if [[ ! -d "$UNITREE_ASSET_DIR" ]]; then
    pushd "$WHOLE_BODY_TRACKING_DIR" >/dev/null
    curl -L -o unitree_description.tar.gz https://storage.googleapis.com/qiayuanl_robot_descriptions/unitree_description.tar.gz
    tar -xzf unitree_description.tar.gz -C source/whole_body_tracking/whole_body_tracking/assets/
    rm -f unitree_description.tar.gz
    popd >/dev/null
fi

pushd "$WHOLE_BODY_TRACKING_DIR" >/dev/null
python -m pip install -e source/whole_body_tracking
popd >/dev/null

python "$REPO_ROOT/scripts/check_beyondmimic_isaaclab210.py" --isaaclab-dir "$ISAACLAB_DIR"

cat <<EOF
Setup complete.

Environment prefix:
  $ENV_PREFIX

Cache directories:
  CONDA_PKGS_DIRS=$CONDA_PKGS_DIRS
  PIP_CACHE_DIR=$PIP_CACHE_DIR
  XDG_CACHE_HOME=$XDG_CACHE_HOME
  TMPDIR=$TMPDIR
  WHEELHOUSE_DIR=$WHEELHOUSE_DIR

Isaac Sim:
  ISAACSIM_VERSION=$ISAACSIM_VERSION
  INSTALL_EXTSCACHE=$INSTALL_EXTSCACHE

Next steps:
  source $CONDA_BASE/etc/profile.d/conda.sh
  conda activate $ENV_PREFIX
  isaacsim --help
  cd $WHOLE_BODY_TRACKING_DIR
  python scripts/replay_npz.py --motion_file <path_to_motion_npz> --device cuda:0 --headless
EOF
