#!/usr/bin/env bash
# ProtoMotions MuJoCo (CPU) installer
# Usage: ./install.sh [env_name]
set -euo pipefail

ENV_NAME="${1:-protomotions_mujoco}"
PY_VERSION="3.10"

# Optional PyPI mirror; useful if direct PyPI is slow/unreachable.
case "${PYPI_MIRROR:-}" in
    "")     PYPI_EXTRA_INDEX="" ;;
    tuna)   PYPI_EXTRA_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple" ;;
    aliyun) PYPI_EXTRA_INDEX="https://mirrors.aliyun.com/pypi/simple/" ;;
    *)      PYPI_EXTRA_INDEX="$PYPI_MIRROR" ;;
esac

PIP_NET_FLAGS=(--retries 10 --timeout 180)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cap parallel build jobs (openmesh's C++ templates can eat 1.5-2.5 GB per cc1plus;
# unlimited -j on 20 cores risks swap thrash and UI freezes). Override by exporting
# BUILD_JOBS=N before invoking.
BUILD_JOBS="${BUILD_JOBS:-12}"
export MAX_JOBS="$BUILD_JOBS"
export CMAKE_BUILD_PARALLEL_LEVEL="$BUILD_JOBS"
export MAKEFLAGS="-j$BUILD_JOBS"

# ----- locate conda --------------------------------------------------------
if command -v conda >/dev/null 2>&1; then
    CONDA_BIN="$(command -v conda)"
elif [[ -x "$HOME/miniconda3/bin/conda" ]]; then
    CONDA_BIN="$HOME/miniconda3/bin/conda"
elif [[ -x "$HOME/anaconda3/bin/conda" ]]; then
    CONDA_BIN="$HOME/anaconda3/bin/conda"
else
    echo "ERROR: conda not found. Install Miniconda first." >&2
    exit 1
fi
CONDA_BASE="$("$CONDA_BIN" info --base)"
# shellcheck disable=SC1091
source "$CONDA_BASE/etc/profile.d/conda.sh"

echo "[1/6] Using conda at: $CONDA_BIN"
echo "      Target env:     $ENV_NAME (python $PY_VERSION)"

# ----- create / reuse env --------------------------------------------------
if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    echo "[2/6] Env '$ENV_NAME' already exists, reusing."
else
    echo "[2/6] Creating env '$ENV_NAME'..."
    conda create -y -n "$ENV_NAME" "python=$PY_VERSION" pip
fi
conda activate "$ENV_NAME"
if [[ "${CONDA_DEFAULT_ENV:-}" != "$ENV_NAME" ]]; then
    echo "ERROR: failed to activate env $ENV_NAME" >&2
    exit 1
fi
python -m pip install --upgrade pip

# ----- build tools (openmesh wheel build needs cmake) ----------------------
# Pin cmake < 4: openmesh 1.2.1's CMakeLists.txt declares a minimum < 3.5,
# which CMake 4 rejected when it dropped that compatibility shim.
echo "[3/6] Installing build tools (cmake<4) into env..."
conda install -y -c conda-forge "cmake<4" make

# ----- CPU PyTorch ---------------------------------------------------------
echo "[4/6] Installing PyTorch (CPU)..."
TORCH_PIP_ARGS=(--index-url "https://download.pytorch.org/whl/cpu")
if [[ -n "$PYPI_EXTRA_INDEX" ]]; then
    TORCH_PIP_ARGS+=(--extra-index-url "$PYPI_EXTRA_INDEX")
fi
python -m pip install "${PIP_NET_FLAGS[@]}" "${TORCH_PIP_ARGS[@]}" \
    torch torchvision torchaudio

# ----- ProtoMotions + MuJoCo deps ------------------------------------------
echo "[5/6] Installing ProtoMotions (editable) + MuJoCo requirements..."
cd "$REPO_ROOT"
EXTRA_ARGS=()
if [[ -n "$PYPI_EXTRA_INDEX" ]]; then
    EXTRA_ARGS+=(--extra-index-url "$PYPI_EXTRA_INDEX")
fi
python -m pip install "${PIP_NET_FLAGS[@]}" "${EXTRA_ARGS[@]}" -e .
python -m pip install "${PIP_NET_FLAGS[@]}" "${EXTRA_ARGS[@]}" -r requirements_mujoco.txt

# ----- pre-package bundled kimodo example motions --------------------------
echo "[6/6] Packaging bundled kimodo example motions into a MotionLib..."
KIMODO_PROTO_DIR="$REPO_ROOT/data/g1-kimodo-generated/proto"
KIMODO_PT="$REPO_ROOT/data/g1-kimodo-generated/kimodo_g1_bundled.pt"
if [[ ! -d "$KIMODO_PROTO_DIR" ]]; then
    echo "      $KIMODO_PROTO_DIR not found, skipping."
elif [[ -f "$KIMODO_PT" ]] && [[ "${PROTOMOTIONS_FORCE_REPACK:-0}" != "1" ]]; then
    echo "      $KIMODO_PT exists, reusing (PROTOMOTIONS_FORCE_REPACK=1 to rebuild)."
else
    if ! python protomotions/components/motion_lib.py \
            --motion-path "$KIMODO_PROTO_DIR" \
            --output-file "$KIMODO_PT"; then
        echo "WARNING: failed to package kimodo bundled motions; start.sh option 1 will retry."
    fi
fi

echo
echo "Install complete."
echo "  Activate:  conda activate $ENV_NAME"
echo "  Run:       ./start.sh"
