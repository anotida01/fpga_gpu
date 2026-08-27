# Get the directory of the script
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

export PROJ_DIR="$SCRIPT_DIR/"
export RTL_DIR="$SCRIPT_DIR/rtl"
export TESTS_DIR="$SCRIPT_DIR/tests"
export SIM_DIR="$SCRIPT_DIR/sim/new_flow"
export REGRESSION_AREA="$SIM_DIR/runs/"
export QUARTUS_ROOTDIR="${QUARTUS_ROOTDIR:-/home/ano/.local/intelFPGA/22.1std/quartus/}"
