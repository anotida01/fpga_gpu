#!/bin/bash
set -e

# Generate a unique run directory
UUID=$(date +%F_%H-%M-%S)
UUID+="_"
UUID+=$(uuidgen 2>/dev/null | head -c 6 || echo "$RANDOM")

if [ $# -lt 2 ]; then
  echo "Usage: $0 <snapshot> <test_name> [SIM_OPTS]"
  exit 1
fi

SNAPSHOT="$1"
TEST_NAME="$2"
shift 2
SIM_OPTS="$@"

if [ -z "${SIM_DIR}" ]; then
  SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -z "${PROJ_DIR}" ]; then
  PROJ_DIR="$(cd "${SIM_DIR}/../.." && pwd)"
fi
if [ -z "${TESTS_DIR}" ]; then
  TESTS_DIR="${PROJ_DIR}/tests"
fi

export SIM_DIR
export PROJ_DIR
export TESTS_DIR

DEFAULT_SIM_OPTS="-perfstat -covtest ${TEST_NAME} -covoverwrite"
SIM_OPTS+=" ${DEFAULT_SIM_OPTS}"

echo "Snapshot: ${SNAPSHOT}, Test: ${TEST_NAME}, Extra SIM_OPTS: ${SIM_OPTS}"

# Setup scratch symlink in workspace /scratch directory
SCRATCH_PATH="/scratch/${USER}/fpga_gpu_runs"
mkdir -p "${SCRATCH_PATH}"

RUNS_DIR="${SIM_DIR}/runs"
if [ ! -L "${RUNS_DIR}" ] && [ ! -d "${RUNS_DIR}" ]; then
  echo "Creating symlink for ${RUNS_DIR} -> ${SCRATCH_PATH}"
  ln -s "${SCRATCH_PATH}" "${RUNS_DIR}"
fi

WORK_DIR="${RUNS_DIR}/xrun_${TEST_NAME}_${UUID}"
mkdir -p "${WORK_DIR}"

# Update latest symlink
set +e
ln -sfn "$(realpath "${WORK_DIR}")" "${RUNS_DIR}/latest"
set -e

# Link file manifests and xcelium build dir if available
ln -sf "$(realpath "${SIM_DIR}/build_tb.xrun.args")" "${WORK_DIR}/"
ln -sf "$(realpath "${SIM_DIR}/build_tb.xrun.files")" "${WORK_DIR}/"
if [ -d "${TESTS_DIR}/testcases/memh" ]; then
  ln -sf "$(realpath "${TESTS_DIR}/testcases/memh")" "${WORK_DIR}/memh"
fi

if [ -d "${SIM_DIR}/xcelium.d" ]; then
  cp -r "$(realpath "${SIM_DIR}/xcelium.d")" "${WORK_DIR}/."
elif [ -d "./xcelium.d" ]; then
  cp -r "$(realpath ./xcelium.d)" "${WORK_DIR}/."
fi

TEST_FILE="${TESTS_DIR}/testcases/${TEST_NAME}/${TEST_NAME}.sv"
if [ ! -f "${TEST_FILE}" ]; then
  TEST_FILE="${TESTS_DIR}/testcases/${TEST_NAME}.sv"
fi

if [ "${TEST_NAME}" = "tc_axilfe_basic_wr_rd" ]; then
  TOP_MODULE="tb_axfe"
else
  TOP_MODULE="tb_axfe" # Default to axfe for now
fi

set +e
(
  cd "${WORK_DIR}"
  echo "Executing simulation in ${WORK_DIR}..."
  if [ -f "${TEST_FILE}" ]; then
    xrun -f build_tb.xrun.args -f build_tb.xrun.files "${TEST_FILE}" -top "${TOP_MODULE}" -snapshot "${SNAPSHOT}" +UVM_TESTNAME="${TEST_NAME}" ${SIM_OPTS}
  else
    xrun -f build_tb.xrun.args -f build_tb.xrun.files -top "${TOP_MODULE}" -snapshot "${SNAPSHOT}" +UVM_TESTNAME="${TEST_NAME}" ${SIM_OPTS}
  fi
)
EXIT_CODE=$?
echo "Simulation finished with exit code: ${EXIT_CODE}"
exit ${EXIT_CODE}
