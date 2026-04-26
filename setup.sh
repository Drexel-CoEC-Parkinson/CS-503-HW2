#!/bin/bash
# ============================================================================
#  CS 503 — HW2 setup script
#  Generates test data for validate.sh, organize.sh, and pipeline.sh.
#
#  Idempotent: safe to run multiple times. Each run regenerates drop/ and
#  data-source/ from scratch (deterministically). Your own scripts and any
#  archive/ quarantine/ output/ logs/ directories are left untouched.
#
#  Author: Drew Parkinson (CS 503, Spring 2026)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> HW2 setup"
echo "    Working in: $SCRIPT_DIR"

# ----------------------------------------------------------------------------
# Make sure pipeline.conf exists. We never overwrite a student's edits;
# we only seed it from the .example if it's missing.
# ----------------------------------------------------------------------------
if [ -f pipeline.conf.example ]; then
    if [ ! -f pipeline.conf ]; then
        cp pipeline.conf.example pipeline.conf
        echo "    Created pipeline.conf (copied from pipeline.conf.example)"
    else
        echo "    Keeping existing pipeline.conf (run cp pipeline.conf.example pipeline.conf to reset)"
    fi
else
    echo "    Warning: pipeline.conf.example not found; skipping pipeline.conf creation"
fi

# ----------------------------------------------------------------------------
# Helper: emit a clean CSV to stdout.
#   Args: $1 = numeric seed, $2 = number of data rows, $3 = ISO date string
# Output schema: transaction_id,date,store_id,product,units,revenue,status
# ----------------------------------------------------------------------------
gen_csv() {
    local seed="$1"
    local rows="$2"
    local row_date="$3"

    # Note: we don't use awk's built-in rand()/srand() because mawk and gawk
    # don't always agree on what srand(seed) means. Instead, we implement a
    # Park-Miller LCG by hand; this is deterministic across every awk impl.
    awk -v seed="$seed" -v rows="$rows" -v rdate="$row_date" '
    function nextrand() {
        rng_state = (16807 * rng_state) % 2147483647
        return rng_state / 2147483647
    }
    BEGIN {
        rng_state = seed
        printf "transaction_id,date,store_id,product,units,revenue,status\n"

        n_products = split("widget-a widget-b gadget-x gadget-y tool-pro tool-lite kit-basic kit-deluxe", products, " ")
        # Status pool weighted toward "completed" so the filter does meaningful work
        n_statuses = split("completed completed completed completed completed completed refunded pending cancelled", statuses, " ")

        for (i = 1; i <= rows; i++) {
            tid       = sprintf("T%08d", seed * 100000 + i)
            store     = sprintf("store_%03d", int(nextrand() * 200) + 1)
            product   = products[int(nextrand() * n_products) + 1]
            units     = int(nextrand() * 10) + 1
            unitprice = (int(nextrand() * 9000) + 500) / 100   # $5.00 .. $94.99
            revenue   = sprintf("%.2f", unitprice * units)
            status    = statuses[int(nextrand() * n_statuses) + 1]

            printf "%s,%s,%s,%s,%d,%s,%s\n", tid, rdate, store, product, units, revenue, status
        }
    }'
}

# ============================================================================
#  drop/ — six CSVs designed to exercise every validation check
# ============================================================================
echo "==> Generating drop/"
rm -rf drop
mkdir -p drop

# (1) Clean, valid (control case)
echo "    drop/daily-2026-04-01.csv  [clean valid]"
gen_csv 101 50 "2026-04-01" > drop/daily-2026-04-01.csv
touch -d "2026-04-01" drop/daily-2026-04-01.csv

# (2) CRLF line endings (Windows export simulation)
echo "    drop/daily-2026-04-02.csv  [CRLF line endings]"
gen_csv 102 50 "2026-04-02" | sed 's/$/\r/' > drop/daily-2026-04-02.csv
touch -d "2026-04-02" drop/daily-2026-04-02.csv

# (3) Leading/trailing whitespace inside specific fields (deterministic pattern)
echo "    drop/daily-2026-04-03.csv  [whitespace in fields]"
gen_csv 103 50 "2026-04-03" \
  | awk -F',' '
      BEGIN { OFS="," }
      NR == 1 { print; next }
      {
          $1 = $1 " "          # trailing space on transaction_id
          $3 = " " $3          # leading space on store_id
          $6 = $6 " "          # trailing space on revenue
          print
      }' > drop/daily-2026-04-03.csv
touch -d "2026-04-03" drop/daily-2026-04-03.csv

# (4) Duplicate rows (three duplicates appended at the end of the file)
echo "    drop/daily-2026-04-04.csv  [duplicate rows]"
gen_csv 104 50 "2026-04-04" > drop/daily-2026-04-04.csv
{
    sed -n '5p'  drop/daily-2026-04-04.csv
    sed -n '15p' drop/daily-2026-04-04.csv
    sed -n '25p' drop/daily-2026-04-04.csv
} >> drop/daily-2026-04-04.csv
touch -d "2026-04-04" drop/daily-2026-04-04.csv

# (5) Wrong column count on row 23 (last two fields stripped)
echo "    drop/daily-2026-04-05.csv  [column count error on one row]"
gen_csv 105 50 "2026-04-05" \
  | awk 'NR == 23 { sub(/,[^,]*,[^,]*$/, ""); print; next } { print }' \
  > drop/daily-2026-04-05.csv
touch -d "2026-04-05" drop/daily-2026-04-05.csv

# (6) Missing header row
echo "    drop/daily-2026-04-06.csv  [missing header row]"
gen_csv 106 50 "2026-04-06" | tail -n +2 > drop/daily-2026-04-06.csv
touch -d "2026-04-06" drop/daily-2026-04-06.csv

# ============================================================================
#  data-source/ — eight daily report CSVs for pipeline.sh
#  Seven are clean; one (daily-2026-05-03.csv) has CRLF line endings so the
#  pipeline's validation stage has a real failure to report.
# ============================================================================
echo "==> Generating data-source/"
rm -rf data-source
mkdir -p data-source

# Format: "YYYY-MM-DD:seed:rows"
clean_files=(
    "2026-04-01:201:140"
    "2026-04-08:202:155"
    "2026-04-15:203:170"
    "2026-04-22:204:140"
    "2026-04-29:205:160"
    "2026-05-10:207:150"
    "2026-05-17:209:145"
)

for entry in "${clean_files[@]}"; do
    file_date="${entry%%:*}"
    rest="${entry#*:}"
    seed="${rest%%:*}"
    rows="${rest##*:}"
    file="data-source/daily-${file_date}.csv"
    echo "    $file  [valid, $rows rows]"
    gen_csv "$seed" "$rows" "$file_date" > "$file"
    touch -d "$file_date" "$file"
done

# The intentionally-invalid one (CRLF endings)
echo "    data-source/daily-2026-05-03.csv  [INVALID — CRLF line endings, 130 rows]"
gen_csv 208 130 "2026-05-03" | sed 's/$/\r/' > data-source/daily-2026-05-03.csv
touch -d "2026-05-03" data-source/daily-2026-05-03.csv

# ============================================================================
echo "==> Setup complete"
echo ""
echo "drop/         (for organize.sh):"
ls -1 drop/ | sed 's/^/   /'
echo ""
echo "data-source/  (for pipeline.sh):"
ls -1 data-source/ | sed 's/^/   /'
echo ""
echo "Next steps:"
echo "  - Read README.md"
echo "  - Start with validate.sh"
echo "  - Run ./setup.sh again any time you want a clean slate."
