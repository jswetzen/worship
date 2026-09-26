#!/usr/bin/env bash
# Build one zip of .onsong charts per set list.
#
#   ./build-sets.sh                 # every sets/*.txt -> dist/<name>.zip
#   ./build-sets.sh sets/MEG26.txt  # just that one
#
# A set list is a plain text file with one song title per line, in set order,
# so a list can be pasted straight from a chat message. Blank lines and lines
# starting with # are ignored. Charts are looked up here and in the Swedish
# repo ($SWEDISH_DIR: ./worship-swedish, where the release workflow checks it
# out, or else the sibling checkout ../worship-swedish).
#
# Matching ignores case, punctuation, list bullets and the invisible
# word-joiner characters that chat apps paste in (a list pasted on 2026-09-26
# had U+2060 in front of most titles). A line matches a chart when it equals
# the file name or the chart's Title:, or failing that when the file name or
# Title: starts with it at a word boundary, so "Broken vessels" finds
# "Broken Vessels (Amazing Grace)". A line that matches nothing, or more than
# one chart, is reported and skipped rather than failing the build: a set is
# still worth having with one song missing, and the warning says which. Put
# the full title in the set file to settle an ambiguity -- e.g. "Majesty"
# matches Majesty.onsong exactly, which is a different song from
# "Majesty (Here I Am)".
#
# The zip holds the charts under their own file names, same as
# worshipsongs.zip, so importing it into OnSong updates the songs already
# there instead of creating renamed copies.

set -euo pipefail
# [:alnum:] and \L must understand å/ä/ö, and the runner's default locale
# may not be UTF-8.
export LC_ALL=C.UTF-8

cd "$(dirname "$0")"

if [[ -z "${SWEDISH_DIR:-}" ]]; then
  if [[ -d worship-swedish ]]; then SWEDISH_DIR=worship-swedish
  else SWEDISH_DIR=../worship-swedish; fi
fi
OUT_DIR=${OUT_DIR:-dist}

# Lower-case, turn every run of non-alphanumerics (punctuation, bullets,
# U+2060, stray \r) into one space, and trim. One title per input line.
norm() { sed -E 's/.*/\L&/; s/[^[:alnum:]]+/ /g; s/^ +| +$//g'; }

# Index every chart once: parallel arrays of path, normalised file name and
# normalised Title: (falling back to the first line, which is where OnSong
# puts the title when there is no Title: tag). Empty files are left out so
# awk's one-line-per-file output stays aligned with the path list.
mapfile -t paths < <(find . "$SWEDISH_DIR" -maxdepth 1 -name '*.onsong' -size +0 \
  2>/dev/null | sort)
if (( ${#paths[@]} == 0 )); then echo "no .onsong charts found" >&2; exit 1; fi
mapfile -t stems < <(for p in "${paths[@]}"; do b=${p##*/}; echo "${b%.onsong}"; done | norm)
mapfile -t titles < <(awk '
  FNR == 1 { if (NR > 1) print t; t = $0; got = 0 }
  !got && /^[Tt]itle:/ { t = $0; sub(/^[Tt]itle:[ \t]*/, "", t); got = 1 }
  END { print t }' "${paths[@]}" | norm)

build_set() {
  local list=$1 name zip line q i found=0 skipped=0
  local -a hits files=()
  name=$(basename "$list" .txt)
  zip="$OUT_DIR/$name.zip"
  echo "== $name"

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    q=$(printf '%s\n' "$line" | norm)
    [[ -z $q ]] && continue

    hits=()
    for i in "${!paths[@]}"; do
      [[ ${stems[i]} == "$q" || ${titles[i]} == "$q" ]] && hits+=("$i")
    done
    if (( ${#hits[@]} == 0 )); then
      for i in "${!paths[@]}"; do
        [[ ${stems[i]} == "$q "* || ${titles[i]} == "$q "* ]] && hits+=("$i")
      done
    fi

    if (( ${#hits[@]} == 1 )); then
      files+=("${paths[hits[0]]}")
      echo "   ok       $line -> ${paths[hits[0]]##*/}"
      found=$((found + 1))
    elif (( ${#hits[@]} == 0 )); then
      echo "   MISSING  $line" >&2
      skipped=$((skipped + 1))
    else
      echo "   AMBIGUOUS $line -> $(for i in "${hits[@]}"; do printf '"%s" ' "${paths[i]##*/}"; done)" >&2
      skipped=$((skipped + 1))
    fi
  done < "$list"

  mkdir -p "$OUT_DIR"
  rm -f "$zip"   # zip adds to an existing archive; start clean
  if (( found > 0 )); then
    zip -q -j "$zip" "${files[@]}"
  fi
  echo "   $found songs -> $zip$( (( skipped )) && echo ", $skipped skipped")"
}

if (( $# == 0 )); then set -- sets/*.txt; fi
for list in "$@"; do build_set "$list"; done
