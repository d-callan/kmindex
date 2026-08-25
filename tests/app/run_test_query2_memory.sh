#!/usr/bin/env bash

kmindex_bin=$1
data_dir=$2
fail=0

cd "$data_dir"

# Test 1: query2 with --memory-budget 0 matches no flag (no limit, current behavior)
rm -rf out_zero out_noflag

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_zero -t 4 --memory-budget 0 2> /dev/null

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_noflag -t 4 2> /dev/null

diff out_zero/pa.tsv out_noflag/pa.tsv || { echo "FAIL: budget=0 differs from no flag (pa)"; fail=1; }
diff out_zero/abs.tsv out_noflag/abs.tsv || { echo "FAIL: budget=0 differs from no flag (abs)"; fail=1; }

# Test 2: tight budget (1MB) still produces correct output
rm -rf out_tiny

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_tiny -t 4 --memory-budget 1 2> /dev/null

diff out_tiny/pa.tsv out_noflag/pa.tsv || { echo "FAIL: tight budget produces different output (pa)"; fail=1; }
diff out_tiny/abs.tsv out_noflag/abs.tsv || { echo "FAIL: tight budget produces different output (abs)"; fail=1; }

# Test 3: --fast + budget produces correct output (exercises --fast code path in memory estimate)
rm -rf out_fast_budget out_fast_nobudget

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_fast_budget -t 2 --memory-budget 1 --fast 2> /dev/null

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_fast_nobudget -t 2 --fast 2> /dev/null

diff out_fast_budget/pa.tsv out_fast_nobudget/pa.tsv || { echo "FAIL: --fast+budget differs from --fast (pa)"; fail=1; }
diff out_fast_budget/abs.tsv out_fast_nobudget/abs.tsv || { echo "FAIL: --fast+budget differs from --fast (abs)"; fail=1; }
diff out_fast_budget/pa.tsv out_noflag/pa.tsv || { echo "FAIL: --fast+budget differs from baseline (pa)"; fail=1; }
diff out_fast_budget/abs.tsv out_noflag/abs.tsv || { echo "FAIL: --fast+budget differs from baseline (abs)"; fail=1; }

# Test 4: position format (json_vec) + budget produces correct output
# Exercises phase 2 positions_mem path in memory estimate for both bw==1 (pa) and bw>1 (abs)
rm -rf out_pos_budget out_pos_nobudget

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f json_vec -o out_pos_budget -t 2 --memory-budget 1 2> /dev/null

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f json_vec -o out_pos_nobudget -t 2 2> /dev/null

diff out_pos_budget/abs.json out_pos_nobudget/abs.json || { echo "FAIL: position format + budget differs (abs)"; fail=1; }
diff out_pos_budget/pa.json out_pos_nobudget/pa.json || { echo "FAIL: position format + budget differs (pa)"; fail=1; }

# Test 5: oversized index warning — budget too small for any single index should emit a warning.
# Output correctness is already verified by Test 2 (same 1MB budget); here we only check the warning.
rm -rf out_oversized
stderr_file=$(mktemp)

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_oversized -t 2 --memory-budget 1 2> "$stderr_file"

if ! grep -q "will run alone" "$stderr_file"; then
  echo "FAIL: oversized index should emit 'will run alone' warning"; fail=1
fi
rm -f "$stderr_file"

# Test 6: multi-index paths + memory budget produces same output as single global index
# Verifies memory gating works with merged indexes from comma-separated --index paths
rm -rf out_multi_budget out_single

${kmindex_bin} query2 -i indexes/abs_global,indexes/pa_global \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_multi_budget -t 2 --memory-budget 1 2> /dev/null

${kmindex_bin} query2 -i indexes/index \
  -q datasets/pa_dataset/1.fasta \
  -z 5 -f matrix -o out_single -t 2 2> /dev/null

diff out_multi_budget/abs.tsv out_single/abs.tsv || { echo "FAIL: multi-index+budget differs from single (abs)"; fail=1; }
diff out_multi_budget/pa.tsv out_single/pa.tsv || { echo "FAIL: multi-index+budget differs from single (pa)"; fail=1; }

rm -rf out_zero out_noflag out_tiny out_fast_budget out_fast_nobudget out_pos_budget out_pos_nobudget out_oversized out_multi_budget out_single

if [ $fail -eq 0 ]; then
  echo "All query2 memory-gating tests passed."
  exit 0
else
  exit 1
fi
