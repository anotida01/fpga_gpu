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

DEFAULT_SIM_OPTS="-perfstat -covtest ${TEST_NAME}"
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

SNAPSHOTS_FILE="${SIM_DIR}/snapshots.txt"
TOP_MODULE=$(awk -v s="$SNAPSHOT" 'NF>=2 && $1==s {print $2; exit}' "${SNAPSHOTS_FILE}")

if [ -z "$TOP_MODULE" ]; then
  echo "ERROR: snapshot '${SNAPSHOT}' not found in ${SNAPSHOTS_FILE}"
  echo "       Add a row (snapshot tb_top) to ${SNAPSHOTS_FILE}"
  exit 1
fi
TB_FILES="${SIM_DIR}/build_tb.xrun.files"
if [ ! -f "${TB_FILES}" ]; then
  echo "ERROR: TB filelist not found: ${TB_FILES}"
  exit 1
fi

TEST_FILE="${TESTS_DIR}/testcases/${TEST_NAME}.sv"

# The snapshot holds the DUT (elaborated at the DUT top).
# Here we compile the testbench harness (VIP + UVM env + tb_<level>) and the
# testcase fresh at run time, with the run top = tb_<level>.
ln -sf "$(realpath "${SIM_DIR}/build_tb.xrun.args")" "${WORK_DIR}/"
ln -sf "$(realpath "${SIM_DIR}/run_sim.xrun.args")" "${WORK_DIR}/"
ln -sf "$(realpath "${TB_FILES}")" "${WORK_DIR}/"
if [ -d "${TESTS_DIR}/testcases/memh" ]; then
  ln -sf "$(realpath "${TESTS_DIR}/testcases/memh")" "${WORK_DIR}/memh"
fi

if [ -d "${SIM_DIR}/xcelium.d" ]; then
  cp -r "$(realpath "${SIM_DIR}/xcelium.d")" "${WORK_DIR}/."
elif [ -d "./xcelium.d" ]; then
  cp -r "$(realpath ./xcelium.d)" "${WORK_DIR}/."
fi

set +e
(
  cd "${WORK_DIR}"
  echo "Executing simulation in ${WORK_DIR} (top: ${TOP_MODULE})..."
  TB_RUN_FILE="build_tb.xrun.files"
  if [ -f "${TEST_FILE}" ]; then
    xrun -f build_tb.xrun.args -f run_sim.xrun.args -f "${TB_RUN_FILE}" "${TEST_FILE}" -top "${TOP_MODULE}" -snapshot "${SNAPSHOT}" +UVM_TESTNAME="${TEST_NAME}" ${SIM_OPTS}
  else
    xrun -f build_tb.xrun.args -f run_sim.xrun.args -f "${TB_RUN_FILE}" -top "${TOP_MODULE}" -snapshot "${SNAPSHOT}" +UVM_TESTNAME="${TEST_NAME}" ${SIM_OPTS}
  fi
)
EXIT_CODE=$?
echo "Simulation finished with exit code: ${EXIT_CODE}"
exit ${EXIT_CODE}
