#!/bin/sh
# A reproducible build, for tier-1 (byte-identical) verification.
#
# version.c embeds __DATE__ and __TIME__, so two builds differ by default; gcc
# honours SOURCE_DATE_EPOCH for both, which lets verification pin the timestamp
# while an ordinary build still records the real one.  The Makefile carries no
# -g, so nothing else records a line number.
#
# Cleans first: a stale object from a differently-flagged build is silently
# reused otherwise.
#
# Usage: build.sh <output-path>          (run from the tree root)
set -e
out=$1
export SOURCE_DATE_EPOCH=1700000000
make clean >/dev/null 2>&1 || true
make -j64 >/dev/null
cp vim "$out"
