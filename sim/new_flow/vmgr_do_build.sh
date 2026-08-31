#!/bin/sh

echo "RUNNING VMANAGER BUILD SCRIPT: $0 ..."

if [ -z "${SIM_DIR}" ]; then
  SIM_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
fi
export SIM_DIR

SNAPSHOTS_FILE="${SIM_DIR}/snapshots.txt"

if [ ! -f "${SNAPSHOTS_FILE}" ]; then
  echo "ERROR: snapshots file not found: ${SNAPSHOTS_FILE}"
  exit 1
fi

f_option=""
if [ -n "$BRUN_HDL_FILES" ]; then
  for hdl_file in ${BRUN_HDL_FILES}; do
    if [ -f "$hdl_file" ]; then
      f_option="$f_option -f ${hdl_file}"
    else
      echo "WARNING: hdl_file=${hdl_file} does not exist, ignoring."
    fi
  done
fi

BRUN_SESSION_DIR="${BRUN_SESSION_DIR:-./vmgr_session}"

echo "Building snapshots from ${SNAPSHOTS_FILE} ..."

BUILD_FAILURES=0
while IFS= read -r line || [ -n "$line" ]; do
  # Strip leading whitespace
  snap_line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
  # Skip blank lines
  [ -z "$snap_line" ] && continue
  # Skip comments
  case "$snap_line" in \#*) continue ;; esac

  snap_name=$(printf '%s' "$snap_line" | awk '{print $1}')
  top_module=$(printf '%s' "$snap_line" | awk '{print $2}')

  if [ -z "$top_module" ]; then
    echo "ERROR: Malformed pairing (missing top_module): ${snap_line}"
    BUILD_FAILURES=$((BUILD_FAILURES + 1))
    continue
  fi

  echo "Building snapshot: ${snap_name} (top: ${top_module})"
  cmd="xrun -c ${f_option} -snapshot ${snap_name} -top ${top_module} -xmlibdirpath ${BRUN_SESSION_DIR}"
  echo "Executing: $cmd"
  eval "$cmd"
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "ERROR: Build failed for snapshot ${snap_name} (exit code ${rc}). Continuing with next pairing."
    BUILD_FAILURES=$((BUILD_FAILURES + 1))
  fi
done < "${SNAPSHOTS_FILE}"

if [ $BUILD_FAILURES -ne 0 ]; then
  echo "BUILD INCOMPLETE: ${BUILD_FAILURES} snapshot(s) failed to build."
  exit 1
fi

echo "All snapshot builds completed."
exit 0
