#!/usr/bin/bash

# exit on error
set -e

# Check if a test name is provided as an argument
if [ $# -eq 0 ]; then
  echo "Error: Test name must be provided as an argument." >&2
  exit 1
fi

TEST_NAME=$1

xrun -gui \
     -xmvlogargs "-messages -sv -linedebug" \
     -xmelabargs "-access +w+r+c -timescale 1ps/1ps" \
     -f ../common.f \
     -f ../../tests/testcases/$TEST_NAME/$TEST_NAME.f \
     -top top
