#!/usr/bin/env bash

kmindex_bin=$1
directory=$2

cd ${directory}

fail=0

# Test 1: query2 with comma-separated individual index paths
# should produce the same results as query2 with a single global index.
#
# indexes/index has both sub-indexes (abs, pa) in one global index.
# indexes/abs_global has only abs, indexes/pa_global has only pa.
# Passing comma-separated: abs_global,pa_global should merge them.

rm -rf out_multi out_single

# Run query2 with merged comma-separated paths (matrix format)
${kmindex_bin} query2 -i indexes/abs_global,indexes/pa_global \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_multi -t 2 2> /dev/null

# Run query2 with single global index (matrix format)
${kmindex_bin} query2 -i indexes/index \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_single -t 2 2> /dev/null

# Compare abs output (both should have abs.tsv)
diff out_multi/abs.tsv out_single/abs.tsv || { echo "FAIL: abs.tsv differs (matrix)"; fail=1; }

# Run query2 with merged comma-separated paths (json format)
rm -rf out_multi out_single

${kmindex_bin} query2 -i indexes/abs_global,indexes/pa_global \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f json \
                     -o out_multi -t 2 2> /dev/null

${kmindex_bin} query2 -i indexes/index \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f json \
                     -o out_single -t 2 2> /dev/null

diff out_multi/abs.json out_single/abs.json || { echo "FAIL: abs.json differs"; fail=1; }

# Test 2: query2 with pa dataset
rm -rf out_multi out_single

${kmindex_bin} query2 -i indexes/abs_global,indexes/pa_global \
                     -q datasets/pa_dataset/1.fasta \
                     -z 5 \
                     -f matrix \
                     -o out_multi -t 2 2> /dev/null

${kmindex_bin} query2 -i indexes/index \
                     -q datasets/pa_dataset/1.fasta \
                     -z 5 \
                     -f matrix \
                     -o out_single -t 2 2> /dev/null

diff out_multi/pa.tsv out_single/pa.tsv || { echo "FAIL: pa.tsv differs (matrix)"; fail=1; }

# Test 3: query2 with --names to select a single sub-index from merged set
rm -rf out_multi out_single

${kmindex_bin} query2 -i indexes/abs_global,indexes/pa_global \
                     -n abs \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_multi -t 2 2> /dev/null

${kmindex_bin} query2 -i indexes/index \
                     -n abs \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_single -t 2 2> /dev/null

diff out_multi/abs.tsv out_single/abs.tsv || { echo "FAIL: abs.tsv differs with --names"; fail=1; }

# Test 4: query2 with single path (no comma) — backwards compatibility
rm -rf out_single

${kmindex_bin} query2 -i indexes/index \
                     -n abs \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_single -t 2 2> /dev/null

diff out_single/abs.tsv outputs/q1_z4_abs.tsv || { echo "FAIL: single-path backwards compat"; fail=1; }

# Test 5: query2 with all sub-indexes (default --names all) on merged paths
# verifies both sub-indexes produce output files
rm -rf out_multi out_single

${kmindex_bin} query2 -i indexes/abs_global,indexes/pa_global \
                     -q datasets/pa_dataset/1.fasta \
                     -z 5 \
                     -f matrix \
                     -o out_multi -t 2 2> /dev/null

# Both sub-indexes should produce output
[ -f out_multi/abs.tsv ] || { echo "FAIL: abs.tsv missing from multi output"; fail=1; }
[ -f out_multi/pa.tsv ] || { echo "FAIL: pa.tsv missing from multi output"; fail=1; }

# Test 6: sub-index name collision should fail
rm -rf out_collision
${kmindex_bin} query2 -i indexes/index,indexes/abs_global \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_collision -t 1 2> /dev/null
if [ $? -eq 0 ]; then
  echo "FAIL: expected error on sub-index name collision"; fail=1
fi

# Test 7: invalid path in comma-separated list should be rejected by CLI checker
# CLI checker errors (BCliError) exit with code 0 but prevent the command from running,
# so the output directory should not be created.
rm -rf out_invalid
${kmindex_bin} query2 -i indexes/abs_global,indexes/nonexistent \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_invalid -t 1 2> /dev/null
if [ -d out_invalid ]; then
  echo "FAIL: expected CLI rejection on non-existent path in comma-separated list"; fail=1
fi

# Test 8: reversed merge order should produce same results as original order
rm -rf out_multi out_multi_rev

${kmindex_bin} query2 -i indexes/abs_global,indexes/pa_global \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_multi -t 2 2> /dev/null

${kmindex_bin} query2 -i indexes/pa_global,indexes/abs_global \
                     -q datasets/abs_dataset/1.fasta \
                     -z 4 \
                     -f matrix \
                     -o out_multi_rev -t 2 2> /dev/null

diff out_multi/abs.tsv out_multi_rev/abs.tsv || { echo "FAIL: abs.tsv differs with reversed merge order"; fail=1; }
diff out_multi/pa.tsv out_multi_rev/pa.tsv || { echo "FAIL: pa.tsv differs with reversed merge order"; fail=1; }

rm -rf out_multi out_single out_collision out_invalid out_multi_rev

if [ $fail -eq 0 ]; then
  echo "All query2 multi-index tests passed."
  exit 0
else
  exit 1
fi
