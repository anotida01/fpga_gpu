#!/bin/bash
set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 <snapshot_name>"
  echo "Defaulting snapshot_name to 'gpu_dut_snap'"
  SNAPSHOT_NAME="gpu_dut_snap"
else
  SNAPSHOT_NAME="$1"
fi

if [ -z "${SIM_DIR}" ]; then
  SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -z "${PROJ_DIR}" ]; then
  PROJ_DIR="$(cd "${SIM_DIR}/../.." && pwd)"
fi

if [ -z "${TESTS_DIR}" ]; then
  TESTS_DIR="${PROJ_DIR}/tests"
fi

if [ -z "${QUARTUS_ROOTDIR}" ]; then
  QUARTUS_ROOTDIR="/home/ano/.local/intelFPGA/22.1std/quartus/"
fi

export SIM_DIR
export PROJ_DIR
export TESTS_DIR
export QUARTUS_ROOTDIR

echo "Building DUT snapshot '${SNAPSHOT_NAME}'..."
xrun -c \
  -f "${SIM_DIR}/build_dut.xrun.args" \
  -f "${SIM_DIR}/build_dut.xrun.files" \
  -snapshot "${SNAPSHOT_NAME}"
