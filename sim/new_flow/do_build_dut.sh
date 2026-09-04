#!/bin/bash
set -e

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

SNAPSHOTS_FILE="${SIM_DIR}/snapshots.txt"
if [ ! -f "${SNAPSHOTS_FILE}" ]; then
  echo "ERROR: snapshots file not found: ${SNAPSHOTS_FILE}"
  exit 1
fi

# Optional single-snapshot filter:
#   do_build_dut.sh              -> build every row in snapshots.txt
#   do_build_dut.sh <snap_name>  -> build only that row
FILTER="${1:-}"

# All snapshots share one compiled worklib under SIM_DIR/xcelium.d; each snapshot
# is an elaborated-at-top view of it (xmelab -top <top>), so building a new level
# never invalidates the compiled units from earlier levels.
# NB: -xmlibdirpath is the *containing* dir; xrun creates <path>/xcelium.d.
XMLIB_PARENT="${SIM_DIR}"

BUILD_FAILURES=0
while IFS= read -r line || [ -n "$line" ]; do
  # Strip leading whitespace
  line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
  # Skip blank lines
  [ -z "$line" ] && continue
  # Skip comments
  case "$line" in \#*) continue ;; esac

  snap_name=$(printf '%s' "$line" | awk '{print $1}')
  top_module=$(printf '%s' "$line" | awk '{print $2}')

  if [ -z "$snap_name" ] || [ -z "$top_module" ]; then
    echo "ERROR: Malformed snapshots.txt row (need: snapshot  tb_top): ${line}"
    BUILD_FAILURES=$((BUILD_FAILURES + 1))
    continue
  fi
  tb_files="${SIM_DIR}/build_tb.xrun.files"
  if [ ! -f "$tb_files" ]; then
    echo "ERROR: TB filelist not found: ${tb_files}"
    BUILD_FAILURES=$((BUILD_FAILURES + 1))
    continue
  fi
  if [ -n "$FILTER" ] && [ "$snap_name" != "$FILTER" ]; then
    continue
  fi

  echo "Building snapshot: ${snap_name} (top: ${top_module})"
  set +e
  xrun -c \
    -f "${SIM_DIR}/build_dut.xrun.args" \
    -f "${SIM_DIR}/build_dut.xrun.files" \
    -f "${SIM_DIR}/build_tb.xrun.args" \
    -f "${tb_files}" \
    -top "${top_module}" \
    -snapshot "${snap_name}" \
    -xmlibdirpath "${XMLIB_PARENT}"
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "ERROR: Build failed for snapshot ${snap_name} (exit code ${rc}). Continuing with next row."
    BUILD_FAILURES=$((BUILD_FAILURES + 1))
  fi
done < "${SNAPSHOTS_FILE}"

if [ $BUILD_FAILURES -ne 0 ]; then
  echo "BUILD INCOMPLETE: ${BUILD_FAILURES} snapshot(s) failed to build."
  exit 1
fi

echo "All snapshot builds completed."
exit 0
