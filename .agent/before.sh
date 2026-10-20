#!/bin/sh
lake update
(cd test && lake exe cache get)
lake build
