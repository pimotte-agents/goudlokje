#!/bin/sh
set -e
lake build
lake test
test/e2e/run.sh
