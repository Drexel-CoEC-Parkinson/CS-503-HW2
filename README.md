#CS 503 — HW2: Shell Scripting Project

---

## Overview

In this assignment you will build a small data-processing workflow out of three
cooperating shell scripts. The story is realistic: a fictional retail company
exports daily transaction reports as CSV files. Some are clean. Some have
formatting issues. Your scripts will validate them, organize them on disk, and
aggregate them into a summary.

You will write three Bash scripts:

1. **`validate.sh`** — checks that a CSV file is well-formed; offers a `--fix`
   mode that produces a cleaned-up copy.
2. **`organize.sh`** — watches a drop directory, validates each file, files
   valid ones into a date-based archive, quarantines invalid ones, and logs
   every action.
3. **`pipeline.sh`** — reads a configuration file, scans a source directory of
   CSVs, validates each, filters rows by criteria, merges the results, and
   writes a summary report.

The scripts compose. `organize.sh` calls `validate.sh`. `pipeline.sh` calls
`validate.sh`. Doing it this way mirrors how real shell pipelines are built:
small, focused tools that do one thing well, glued together by other scripts.

### Learning goals

By the end of this assignment you should be comfortable with:

- Writing scripts that take command-line arguments and validate them
- Using conditionals, loops, and exit codes to control flow
- Reading and writing files line-by-line in Bash
- Composing pipelines of standard Unix tools (`grep`, `awk`, `sort`, `uniq`,
  `cut`, `tr`)
- Using a configuration file to make a script reusable
- Handling errors gracefully — printing useful messages and choosing
  appropriate exit codes
- Calling one script from another and reacting to its exit code

### Why this matters across disciplines

Whether your graduate program is in CS, ML, Data Science, Cybersecurity, or
Information Systems, this kind of file-processing automation comes up
constantly. ML pipelines ingest training data from messy sources. Security
investigators triage log files dropped into a watch directory. Data analysts
glue together CSVs from different vendors before loading them into a database.
The specific tools here (Bash, the standard Unix utilities) will reappear in
every Linux-based workflow you touch.

---

## Setup

This assignment is distributed through its own GitHub Classroom link, separate
from any other course repository. You will find the invitation link on
Blackboard under HW2.

### Get the starter code

1. **Click the invitation link** on Blackboard. Accept the assignment. GitHub
   Classroom will create a personal repository for you containing the starter
   files.

2. **Copy the HTTPS clone URL** of your personal repo from GitHub.

3. **Clone the repo** to a convenient location on Tux. The course convention
   is `~/cs503/hw2`:

   ```bash
   cd ~/cs503
   git clone <your-personal-repo-URL> hw2
   cd hw2
   ```

   When prompted for credentials, use your GitHub username and the personal
   access token you set up for HW1. If you cleared your credentials since
   then, follow the same setup steps as in HW1.

4. **Confirm the starter files are there:**

   ```bash
   ls
   ```

   You should see:

   ```
   README.md
   setup.sh
   pipeline.conf.example
   .gitignore
   ```

5. **Run the setup script.** It is idempotent — you can run it as many times
   as you want, and it will not destroy your work:

   ```bash
   ./setup.sh
   ```

After setup, your `hw2/` directory will look like this:

```
hw2/
├── README.md
├── setup.sh
├── pipeline.conf.example
├── pipeline.conf            <- copied from .example if missing
├── drop/                    <- 6 test CSV files for organize.sh
│   ├── daily-2026-04-01.csv
│   ├── daily-2026-04-02.csv
│   └── ...
├── data-source/             <- 8 daily report CSVs for pipeline.sh
│   ├── daily-2026-04-01.csv
│   ├── daily-2026-04-08.csv
│   └── ...
└── (you will add)
    ├── validate.sh
    ├── organize.sh
    └── pipeline.sh
```

The directories `archive/`, `quarantine/`, `output/`, and `logs/` will be
created by your scripts as they run; they are ignored by Git.

### CSV schema

All CSV files in this assignment use the same schema:

```
transaction_id,date,store_id,product,units,revenue,status
T00000001,2026-04-15,store_042,widget-a,3,29.97,completed
T00000002,2026-04-15,store_017,gadget-b,1,49.99,refunded
...
```

| Column | Description |
|---|---|
| `transaction_id` | Unique ID, format `T########` |
| `date` | ISO date `YYYY-MM-DD` |
| `store_id` | Store identifier, format `store_###` |
| `product` | Product code |
| `units` | Integer count |
| `revenue` | Decimal, two places |
| `status` | One of: `completed`, `refunded`, `pending`, `cancelled` |

---

## Part 1: `validate.sh` (30 points)

### Purpose

Check a CSV file against the schema above and report any problems. Optionally
produce a cleaned copy.

### Usage

```
./validate.sh [--fix] [--quiet] <file.csv>
```

| Flag | Behavior |
|---|---|
| `--fix` | Produce a cleaned-up copy at `<file>.fixed.csv` instead of just reporting |
| `--quiet` | Suppress the human-readable report; only set the exit code |
| (none) | Print a report to stderr, set exit code |

### Validation checks

Your script must check for **all** of the following. For each problem found,
print one line to stderr describing it (unless `--quiet` is set):

1. **File exists and is readable** — if not, exit 2 with a usage error
2. **File is non-empty** — fail validation if zero bytes
3. **Header row is present** — first non-blank line must contain the seven
   expected column names in order
4. **Column count is consistent** — every data row has exactly 7
   comma-separated fields
5. **No leading/trailing whitespace in fields** — `" T0001 "` is invalid;
   `"T0001"` is valid
6. **No empty values in required columns** — all seven columns are required
7. **No duplicate rows** — no two data rows are byte-identical
8. **LF line endings only** — no `\r` characters (CRLF is a Windows artifact)

### Exit codes

| Code | Meaning |
|---|---|
| 0 | File is valid (or, with `--fix`, was made valid) |
| 1 | File has at least one validation problem |
| 2 | Usage error (missing argument, file not found, etc.) |

### `--fix` mode

When `--fix` is passed, your script must:

1. Read `<file>.csv`
2. Apply these repairs:
   - Convert CRLF to LF
   - Trim leading/trailing whitespace from every field
   - Remove duplicate data rows (the first occurrence wins)
3. Write the result to `<file>.fixed.csv`
4. Re-validate the fixed file silently
5. Exit 0 if the fix succeeded; exit 1 if problems remain (e.g., wrong column
   count — `--fix` cannot reasonably guess the right values)

The original file should not be modified.

### Example

Given `drop/daily-2026-04-02.csv` (which has CRLF line endings):

```bash
$ ./validate.sh drop/daily-2026-04-02.csv
drop/daily-2026-04-02.csv: line 1: CRLF line ending detected
drop/daily-2026-04-02.csv: line 2: CRLF line ending detected
... (etc.)
INVALID: 47 problem(s) found
$ echo $?
1

$ ./validate.sh --fix drop/daily-2026-04-02.csv
$ ls drop/daily-2026-04-02*
drop/daily-2026-04-02.csv  drop/daily-2026-04-02.fixed.csv
$ ./validate.sh drop/daily-2026-04-02.fixed.csv
$ echo $?
0
```

### Hints

- `wc -l` counts lines; `awk -F','` is convenient for splitting on commas
- `tr -d '\r'` strips carriage returns
- `awk -F',' 'NF != 7'` finds rows with wrong column counts
- `sort | uniq -d` finds duplicate lines
- Read about `[[ ... ]]` vs `[ ... ]` in Bash — the double brackets are friendlier
- Quote your variables: `"$file"` not `$file`. Filenames with spaces will
  break unquoted variables.

---

## Part 2: `organize.sh` (25 points)

### Purpose

Take every file in a drop directory, validate it, and either archive it or
quarantine it. Log every action.

### Usage

```
./organize.sh <drop_dir> <archive_dir> <quarantine_dir>
```

For example:

```
./organize.sh ./drop ./archive ./quarantine
```

### Behavior

For each `.csv` file in `<drop_dir>`:

1. Call `./validate.sh --quiet "$file"` to check it
2. If valid (exit 0):
   - Determine the file's date from its modification time:
     `date -r "$file" +%Y/%m/%d`
   - Move the file to `<archive_dir>/YYYY/MM/DD/<filename>`
   - Create the directory structure if it does not exist
   - Log: `[timestamp] ARCHIVED: <file> -> <archive_path>`
3. If invalid (exit 1):
   - Move the file to `<quarantine_dir>/<filename>`
   - Run validate again (without `--quiet`) and capture stderr to
     `<quarantine_dir>/<filename>.reason`
   - Log: `[timestamp] QUARANTINED: <file> -> <quarantine_path>`
4. If validate.sh itself errored (exit 2 or other):
   - Leave the file in place
   - Log: `[timestamp] ERROR: <file> (validate exited <code>)`

All log lines go to `logs/organize.log` (append mode). Create `logs/` if it
does not exist. Use ISO 8601 timestamps: `2026-04-26T14:23:01`.

### After organize.sh runs

```
archive/
└── 2026/
    └── 04/
        └── 01/
            └── daily-2026-04-01.csv
        └── 02/
            └── daily-2026-04-02.csv
        ...
quarantine/
├── daily-2026-04-04.csv
├── daily-2026-04-04.csv.reason
├── daily-2026-04-06.csv
└── daily-2026-04-06.csv.reason
logs/
└── organize.log
```

### Edge cases your script should handle

- An empty drop directory (do nothing, exit 0)
- A drop directory that does not exist (print error, exit 2)
- Filenames with spaces in them (quote your variables!)
- A file already present at the archive destination — append a counter
  suffix or a timestamp; do not overwrite

### Extra credit (5 points): `--watch` mode

Add a `--watch` flag that, after the initial pass, sleeps for 30 seconds and
re-scans the drop directory, repeating until the user sends SIGINT (Ctrl-C).
On SIGINT, log a clean shutdown message and exit 0. Use `trap` to handle the
signal.

### Hints

- The standard pattern for processing all files of a type:
  ```bash
  for file in "$drop_dir"/*.csv; do
      [ -e "$file" ] || continue   # handles the no-match case
      ...
  done
  ```
- `date -r "$file" +"%Y/%m/%d"` gives you the modification date in path form
- `mkdir -p` creates parent directories as needed and is idempotent
- `mv -i` would prompt on overwrite (you don't want that in a script);
  check destination existence yourself with `[ -e "$dest" ]`

---

## Part 3: `pipeline.sh` (35 points)

### Purpose

Run a configuration-driven processing pipeline against a directory of CSV
files: validate them, filter rows by criteria, merge the survivors, and write
a summary report.

### Usage

```
./pipeline.sh <config_file>
```

For example:

```
./pipeline.sh pipeline.conf
```

### Configuration file format

Plain `KEY=VALUE` lines. Lines starting with `#` and blank lines are ignored.
A working example is provided as `pipeline.conf.example`.

```ini
# pipeline.conf — sample configuration

# Where to read CSV files from
SOURCE_DIR=./data-source

# Filter criteria
FILTER_COLUMN=status
FILTER_VALUE=completed
DATE_COLUMN=date
DATE_AFTER=2026-04-15

# Output
OUTPUT_DIR=./output
MERGED_FILE=merged.csv
REPORT_FILE=summary.txt
```

### Pipeline stages

Your script must execute these four stages in order. After each stage, log
progress to stdout in a clear format (`[1/4] Loading configuration...`).

#### Stage 1: Configuration

- Load the config file
- Verify all required keys are present and non-empty
- Verify `SOURCE_DIR` exists and is readable
- If anything is missing or malformed, print a clear error and exit 2

#### Stage 2: Validate

- Find every `.csv` file in `$SOURCE_DIR`
- For each file, call `./validate.sh --quiet`
- Track which files passed and which failed
- Failed files do not contribute to the merged output, but the failure is
  recorded for the report
- If zero files are found, exit 1 with a clear message

#### Stage 3: Filter and merge

- For each valid CSV, keep only rows where:
  - `$FILTER_COLUMN` equals `$FILTER_VALUE`, AND
  - `$DATE_COLUMN` is on or after `$DATE_AFTER` (string comparison works
    correctly for ISO dates — `"2026-04-20" >= "2026-04-15"` is true)
- Write the merged output (with exactly one header row) to
  `$OUTPUT_DIR/$MERGED_FILE`

#### Stage 4: Report

- Write a summary report to `$OUTPUT_DIR/$REPORT_FILE` with the format below

### Required report format

```
HW2 Pipeline Summary Report
Generated: 2026-04-26T14:23:01

Configuration:
  Source dir:     ./data-source
  Filter:         status = completed
  Date filter:    date >= 2026-04-15
  Output:         output/merged.csv

Validation results:
  CSV files found: 8
  Valid:           7
  Invalid:         1
  Skipped files:
    daily-2026-05-03.csv (3 validation problems)

Row counts:
  Total input rows:        1183
  Rows passing filter:      542
  Rows in merged output:    542

Top 5 stores by total revenue:
  store_042   $14,832.50
  store_017   $11,221.00
  store_103    $9,887.25
  store_054    $8,114.00
  store_088    $7,402.75
```

The "Top 5 stores" section is the analytical payoff — it requires a small
pipeline of `awk`, `sort`, and `head` against the merged CSV.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Pipeline completed successfully |
| 1 | Pipeline ran but at least one stage had recoverable failures (e.g., one or more invalid input files) |
| 2 | Configuration error or unrecoverable failure (no readable source directory, no input files at all, etc.) |

### Hints

- To load a config file safely, parse `KEY=VALUE` lines yourself rather than
  blindly `source`-ing the file. A simple loop with `IFS='='` and a `read`
  works well; you can also use `grep` and `cut`. Sourcing untrusted input is
  a real-world security pattern to be aware of, even if this assignment's
  config is benign.
- For filtering with two conditions in awk:
  ```bash
  awk -F',' -v val="$FILTER_VALUE" -v date="$DATE_AFTER" \
      'NR==1 || ($7 == val && $2 >= date)' file.csv
  ```
  The hard-coded column numbers `$7` and `$2` are simple but fragile —
  computing them from the header row is a nice extension.
- For the top-5-stores aggregation:
  ```bash
  awk -F',' 'NR>1 {totals[$3] += $6} END {for (s in totals) printf "%s\t%.2f\n", s, totals[s]}' merged.csv \
      | sort -t$'\t' -k2 -rn \
      | head -5
  ```
- Get exactly one header line in the merged file by writing the header from
  the first valid input, then appending only the data rows of subsequent files
  (`tail -n +2`).

---

## Submission

Commit and push your three scripts from the root of your HW2 repository:

```bash
cd ~/cs503/hw2
chmod +x validate.sh organize.sh pipeline.sh
git add validate.sh organize.sh pipeline.sh
git commit -m "HW2 submission"
git push
```

Do **not** commit the `drop/`, `data-source/`, `archive/`, `quarantine/`,
`output/`, or `logs/` directories. The provided `.gitignore` excludes them
already; verify with `git status` before pushing that nothing from those
directories is staged.

### Self-check before submitting

Run all three scripts end-to-end on a freshly set-up `hw2/` directory:

```bash
./setup.sh                                   # regenerate test data
./validate.sh drop/daily-2026-04-01.csv      # should exit 0
./validate.sh drop/daily-2026-04-04.csv      # should exit 1
./organize.sh ./drop ./archive ./quarantine
ls archive/2026/04/                          # should have date-named dirs
ls quarantine/                               # should have .reason files
./pipeline.sh pipeline.conf
cat output/summary.txt                       # should match the format above
```

If all of those work, you are in good shape.

---

## Grading

| Component | Points |
|---|---|
| **Part 1: `validate.sh`** | **30** |
| All 8 validation checks correctly identify problems | 16 |
| Correct exit codes (0, 1, 2) | 4 |
| `--fix` produces a correct cleaned file | 8 |
| `--quiet` suppresses output appropriately | 2 |
| **Part 2: `organize.sh`** | **25** |
| Calls `validate.sh` and reacts to its exit code | 5 |
| Archive layout (`YYYY/MM/DD/`) is correct | 6 |
| Quarantine includes `.reason` file with validation errors | 5 |
| Logs every action with timestamp | 5 |
| Handles edge cases (empty dir, missing dir, name collisions) | 4 |
| **Part 3: `pipeline.sh`** | **35** |
| Configuration loading and validation | 6 |
| Validation stage integrates with `validate.sh` | 6 |
| Filtering applies both criteria correctly | 8 |
| Merged output has exactly one header row | 4 |
| Summary report matches the required format | 8 |
| Exit codes are correct | 3 |
| **README and code quality** | **10** |
| Header comment in each script (purpose, usage, author) | 3 |
| Scripts are executable and use a shebang | 2 |
| Variables are quoted; no obvious portability bugs | 3 |
| Code is readable (consistent indentation, useful comments) | 2 |
| **Total** | **100** |
| **Extra credit: `--watch` mode in organize.sh** | **+5** |

---

## Tips and pitfalls

**Quote your variables.** `"$file"` not `$file`. Always. The drop directory
contains filenames designed to be tame, but a real-world drop directory
will eventually receive a file named `Q1 sales final FINAL.csv`. Unquoted
variables turn into a bug factory.

**Use `set -e` carefully.** Adding `set -e` near the top of a script makes
it exit on the first failure. This is great for catching surprises but
disastrous if your script intentionally checks return codes. Pick one approach
per script and be consistent.

**Test with the provided messy files.** Each file in `drop/` was crafted to
exercise a specific validation check. If your `validate.sh` passes
`daily-2026-04-04.csv` (the duplicate-rows file), something is wrong.

**`shellcheck` is your friend.** It catches common bugs:
```bash
shellcheck validate.sh
```
ShellCheck is installed on Tux. Running it before submitting is one of the
highest-leverage things you can do.

**Plan before you code.** Sketch out, on paper or in a comment block, what
each stage of `pipeline.sh` will do and what files exist when. The pipeline
is short by line count but has a lot of moving parts.

**Don't reinvent the wheel.** The standard tools — `grep`, `awk`, `sort`,
`uniq`, `cut`, `tr`, `wc`, `head`, `tail` — can solve almost every problem
in this assignment in a single line. If you find yourself writing a lot of
manual line-by-line Bash, ask whether a Unix utility could do it faster.

**Ask early if you're stuck.** Office hours are Tuesday and Thursday
3:00–4:00 PM. The deadline is forgiving (Late Passes and a partial-credit
Day-1 fallback) but starting two days before the deadline is not a winning
strategy for a three-script project.

Good luck.
