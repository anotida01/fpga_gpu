#!/bin/sh

echo "RUNNING VMANAGER SIM SCRIPT: $0 ..."

debug_option="-linedebug"
debug_option="$debug_option -input \"@database -open waves -default; probe -create -all -depth all -memories -variables\""

pre_run_option=""
post_run_option="-exit"

case $BRUN_RUN_MODE in
  interactive)
    post_run_option="-gui"
    ;;
  interactive_debug)
    pre_run_option="$debug_option"
    post_run_option="-gui"
    ;;
  batch)
    post_run_option="-exit"
    ;;
  batch_debug)
    pre_run_option="$debug_option"
    post_run_option="-exit"
    ;;
  *)
    echo "WARNING: BRUN_RUN_MODE '$BRUN_RUN_MODE' not set or unrecognized. Defaulting to batch mode."
    post_run_option="-exit"
    ;;
esac

f_option=""
if [ -n "$BRUN_TOP_FILES" ]; then
  for top_file in ${BRUN_TOP_FILES}; do
    if [ -f "$top_file" ]; then
      f_option="$f_option -f $top_file"
    else
      echo "WARNING: top_file=$top_file does not exist, ignoring."
    fi
  done
fi

cmd_option=""
if [ -n "$BRUN_CMD_FILES" ]; then
  for cmd_file in ${BRUN_CMD_FILES}; do
    if [ -f "$cmd_file" ]; then
      cmd_option="$cmd_option -f $cmd_file"
    else
      echo "WARNING: cmd_file=$cmd_file does not exist, ignoring."
    fi
  done
fi

tcl_option=""
if [ -n "$BRUN_TCL_FILES" ]; then
  for tcl_file in ${BRUN_TCL_FILES}; do
    if [ -f "$tcl_file" ]; then
      tcl_option="$tcl_option -input $tcl_file"
    else
      echo "WARNING: tcl_file=$tcl_file does not exist, ignoring."
    fi
  done
fi

if [ -z "$BRUN_SESSION_DIR" ]; then
  BRUN_SESSION_DIR="./vmgr_session"
fi

cmd="xrun -R -xmlibdirpath ${BRUN_SESSION_DIR} ${pre_run_option} ${f_option} ${cmd_option} ${tcl_option} ${BRUN_SIM_ARGS} ${post_run_option}"
echo "Running: $cmd"
eval $cmd

exit $?
