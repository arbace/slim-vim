#!/bin/sh
# Every enumerator and its value, from DWARF.  Deleting an enumerator
# renumbers the ones after it, and several enums here are the index of a
# parallel table -- hl_flags[HLF_COUNT], first_autopat[NUM_EVENTS] -- so a
# silent renumbering re-points every later entry.  The build is perfectly
# happy with that; this is the check that is not.
#
# Usage: enumvals.sh <source.c> <out>
set -e
src=$1
out=$2
tmp=$(mktemp -d)
cp "$src" "$tmp/vim.c"
gcc -O0 -g -o "$tmp/vim" "$tmp/vim.c"
readelf --debug-dump=info "$tmp/vim" 2>/dev/null |
  awk '/DW_TAG_enumerator/{f=1;name="";val="";next}
       f&&/DW_AT_name/{sub(/.*: */,"");name=$0}
       f&&/DW_AT_const_value/{sub(/.*: */,"");val=$0;print name"="val;f=0}' |
  sort -u > "$out"
rm -rf "$tmp"
