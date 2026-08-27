#!/bin/sh

echo "RUNNING VMANAGER BUILD SCRIPT: $0 ..."

f_option=""
if [ -n "$BRUN_HDL_FILES" ]; then
  for hdl_file in ${BRUN_HDL_FILES}; do
    if [ -f "$hdl_file" ]; then
      f_option="$f_option -f $hdl_file"
    else
      echo "WARNING: hdl_file=$hdl_file does not exist, ignoring."
    fi
  done
fi

if [ -z "$BRUN_SESSION_DIR" ]; then
  BRUN_SESSION_DIR="./vmgr_session"
fi

cmd="xrun -c ${f_option} -xmlibdirpath ${BRUN_SESSION_DIR} -coverage all -covoverwrite"
echo "Executing: $cmd"
eval $cmd

exit $?
