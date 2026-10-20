#!/bin/sh
(cd test && lake exe cache get)
lake build
