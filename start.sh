#!/usr/bin/env bash
# ProtoMotions G1 quickstart (MuJoCo CPU inference).
# Auto-activates the protomotions_mujoco conda env.
set -euo pipefail

ENV_NAME="${PROTOMOTIONS_ENV:-protomotions_mujoco}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKPOINT="$REPO_ROOT/data/pretrained_models/motion_tracker/g1-bones-deploy/last.ckpt"

# ----- locate + activate conda env ----------------------------------------
if command -v conda >/dev/null 2>&1; then
    CONDA_BIN="$(command -v conda)"
elif [[ -x "$HOME/miniconda3/bin/conda" ]]; then
    CONDA_BIN="$HOME/miniconda3/bin/conda"
elif [[ -x "$HOME/anaconda3/bin/conda" ]]; then
    CONDA_BIN="$HOME/anaconda3/bin/conda"
else
    echo "ERROR: conda not found." >&2; exit 1
fi
CONDA_BASE="$("$CONDA_BIN" info --base)"
# shellcheck disable=SC1091
source "$CONDA_BASE/etc/profile.d/conda.sh"

if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    echo "ERROR: conda env '$ENV_NAME' not found. Run ./install.sh first." >&2
    exit 1
fi
conda activate "$ENV_NAME"
cd "$REPO_ROOT"

if [[ ! -f "$CHECKPOINT" ]]; then
    echo "ERROR: pretrained checkpoint not found:" >&2
    echo "       $CHECKPOINT" >&2
    exit 1
fi

# ----- helpers ------------------------------------------------------------
run_inference () {
    local motion_pt="$1"
    echo
    echo "Running G1 motion-tracker inference (MuJoCo CPU, num_envs=1)..."
    echo "  checkpoint:  $CHECKPOINT"
    echo "  motion file: $motion_pt"
    echo
    python protomotions/inference_agent.py \
        --checkpoint "$CHECKPOINT" \
        --motion-file "$motion_pt" \
        --simulator mujoco \
        --num-envs 1
}

convert_kimodo_csv_dir () {
    local in_dir="$1"
    local out_dir="$2"
    python data/scripts/convert_g1_csv_to_proto.py \
        --input-dir "$in_dir" --output-dir "$out_dir" \
        --input-fps 30 --output-fps 30 \
        --pos-units m --rot-format quat_wxyz --joint-units rad \
        --no-has-header --no-has-frame-column --force-remake
}

package_motion_lib () {
    local proto_dir="$1"
    local out_pt="$2"
    python protomotions/components/motion_lib.py \
        --motion-path "$proto_dir" \
        --output-file "$out_pt"
}

# ----- menu ---------------------------------------------------------------
echo
echo "ProtoMotions G1 quickstart"
echo "  1) Run inference on bundled kimodo example motions"
echo "  2) Run inference on a kimodo CSV (convert + package + run)"
echo "  3) Run inference on an existing .pt MotionLib"
read -r -p "Pick [1/2/3]: " choice

case "$choice" in
1)
    PT="$REPO_ROOT/data/g1-kimodo-generated/kimodo_g1_bundled.pt"
    PROTO_DIR="$REPO_ROOT/data/g1-kimodo-generated/proto"
    if [[ ! -f "$PT" ]]; then
        echo "Bundled MotionLib missing, packaging now..."
        package_motion_lib "$PROTO_DIR" "$PT"
    fi
    run_inference "$PT"
    ;;
2)
    DEFAULT_CSV="/home/jiaxingluo/01_repo/kimodo/motion.csv"
    read -r -p "Path to kimodo G1 CSV [$DEFAULT_CSV]: " csv
    csv="${csv:-$DEFAULT_CSV}"
    if [[ ! -f "$csv" ]]; then
        echo "ERROR: CSV not found: $csv" >&2; exit 1
    fi
    STEM="$(basename "${csv%.csv}")"
    WORK_DIR="$REPO_ROOT/data/user-kimodo/$STEM"
    PROTO_DIR="$WORK_DIR/proto"
    PT="$WORK_DIR/${STEM}.pt"
    mkdir -p "$WORK_DIR"
    cp -f "$csv" "$WORK_DIR/${STEM}.csv"
    echo "Converting CSV -> .motion ..."
    convert_kimodo_csv_dir "$WORK_DIR" "$PROTO_DIR"
    echo "Packaging .motion -> MotionLib ..."
    package_motion_lib "$PROTO_DIR" "$PT"
    run_inference "$PT"
    ;;
3)
    DEFAULT_PT="$REPO_ROOT/data/motion_for_trackers/g1_bones_seed_mini.pt"
    read -r -p "Path to .pt MotionLib [$DEFAULT_PT]: " pt
    pt="${pt:-$DEFAULT_PT}"
    if [[ ! -f "$pt" ]]; then
        echo "ERROR: .pt not found: $pt" >&2; exit 1
    fi
    run_inference "$pt"
    ;;
*)
    echo "Invalid choice." >&2; exit 1 ;;
esac
