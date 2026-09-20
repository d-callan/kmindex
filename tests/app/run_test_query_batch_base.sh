#!/usr/bin/env bash

kmindex_bin=$1
data_dir=$2
fail=0

cd "$data_dir"

# Reference: single batch, no batching flag.
rm -rf out_ref
${kmindex_bin} query -i indexes/index -n pa \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_ref -t 1 2> /dev/null

# Test 1: --batch-size-base 0 is a no-op.
rm -rf out_zero
${kmindex_bin} query -i indexes/index -n pa \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_zero -t 1 --batch-size-base 0 2> /dev/null

diff out_zero/pa.tsv out_ref/pa.tsv || { echo "FAIL: --batch-size-base 0 differs from no flag"; fail=1; }

# Test 2: base batching at -t 1 writes per-batch subdirectories
rm -rf out_base
${kmindex_bin} query -i indexes/index -n pa \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_base -t 1 -B 10000 -a 2> /dev/null

nb_batches=$(find out_base -maxdepth 1 -type d -name 'batch_*' | wc -l)
if [ "$nb_batches" -lt 2 ]; then
  echo "FAIL: -B 10000 should produce several batches, got $nb_batches"; fail=1
fi

sort out_base/pa.tsv > agg_base.tsv
sort out_ref/pa.tsv > agg_ref.tsv
diff agg_base.tsv agg_ref.tsv || { echo "FAIL: aggregated base batches differ from reference"; fail=1; }

# Test 3: a limit smaller than a single sequence (100 bases) must still make progress
rm -rf out_tiny out_tiny_ref
head -40 datasets/pa_dataset/1.fasta > subset.fasta

${kmindex_bin} query -i indexes/index -n pa \
  -q subset.fasta \
  -z 5 -f matrix -o out_tiny_ref -t 1 2> /dev/null

${kmindex_bin} query -i indexes/index -n pa \
  -q subset.fasta \
  -z 5 -f matrix -o out_tiny -t 1 -B 1 -a 2> /dev/null

nb_tiny=$(find out_tiny -maxdepth 1 -type d -name 'batch_*' | wc -l)
if [ "$nb_tiny" -ne 20 ]; then
  echo "FAIL: -B 1 should put one sequence per batch, expected 20 batches, got $nb_tiny"; fail=1
fi

sort out_tiny/pa.tsv > agg_tiny.tsv
sort out_tiny_ref/pa.tsv > agg_tiny_ref.tsv
diff agg_tiny.tsv agg_tiny_ref.tsv || { echo "FAIL: -B 1 differs from reference"; fail=1; }

# Test 4: --batch-size-base overrides --batch-size, with a warning.
rm -rf out_both
stderr_file=$(mktemp)
${kmindex_bin} query -i indexes/index -n pa \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_both -t 1 -b 10 -B 10000 -a 2> "$stderr_file"

if ! grep -q "ignoring --batch-size" "$stderr_file"; then
  echo "FAIL: --batch-size-base + --batch-size should warn that --batch-size is ignored"; fail=1
fi

nb_both=$(find out_both -maxdepth 1 -type d -name 'batch_*' | wc -l)
if [ "$nb_both" -ne "$nb_batches" ]; then
  echo "FAIL: -b should be ignored, expected $nb_batches batches, got $nb_both"; fail=1
fi

sort out_both/pa.tsv > agg_both.tsv
diff agg_both.tsv agg_ref.tsv || { echo "FAIL: overridden --batch-size run differs from reference"; fail=1; }
rm -f "$stderr_file"

# Test 5: base batching with several threads stays correct.
rm -rf out_mt
${kmindex_bin} query -i indexes/index -n pa \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_mt -t 4 -B 10000 -a 2> /dev/null

sort out_mt/pa.tsv > agg_mt.tsv
diff agg_mt.tsv agg_ref.tsv || { echo "FAIL: multi-threaded base batching differs from reference"; fail=1; }

rm -rf out_ref out_zero out_base out_tiny out_tiny_ref out_both out_mt
rm -f agg_base.tsv agg_ref.tsv agg_tiny.tsv agg_tiny_ref.tsv agg_both.tsv agg_mt.tsv subset.fasta

if [ $fail -eq 0 ]; then
  echo "All query --batch-size-base tests passed."
  exit 0
else
  exit 1
fi
