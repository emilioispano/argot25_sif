#!/usr/bin/env bash

set -euo pipefail

# -----------------------------
# Default values
# -----------------------------
diamond="/argot25/bin/diamond"
argot="java -jar /argot25/bin/Argot3-1.0.jar"
makedb=0
predict=0

# -----------------------------
# Usage function
# -----------------------------
usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -s <source>       Source FASTA to build database from"
    echo "  -d <db>           DIAMOND database name (prefix, not .dmnd)"
    echo "  -f <fasta>        Input FASTA file for DIAMOND/Argot"
    echo "  -o <outdir>       Output directory for results"
    echo "  -t <threads>      Number of threads (default: 1)"
    echo "  -m                Build DIAMOND database (makedb mode)"
    echo "  -p                Run Argot3 prediction pipeline (predict mode)"
    echo "  -h                Show this help message"
    echo
    echo "Example:"
    echo "  $0 -f query.fasta -d db/diamond_db -s source.fasta -o results -t 16 -m -p"
    exit 1
}

# -----------------------------
# Parse command-line options
# -----------------------------
threads=1
diamond_fasta=""
diamond_db=""
source_fasta=""
results=""

while getopts ":s:d:f:o:t:mph" opt; do
    case $opt in
        s) diamond_fasta=$OPTARG ;;
        d) diamond_db=$OPTARG ;;
        f) source_fasta=$OPTARG ;;
        o) results=$OPTARG ;;
        t) threads=$OPTARG ;;
        m) makedb=1 ;;
        p) predict=1 ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
    esac
done

# -----------------------------
# Check required arguments
# -----------------------------
if [[ $makedb -eq 1 && ( -z "$diamond_fasta" || -z "$diamond_db" ) ]]; then
    echo "Error: -s <source>, -d <db> are required when using -m (makedb mode)"
    exit 1
fi

if [[ $predict -eq 1 && ( -z "$diamond_db" || -z "$source_fasta" || -z "$results" ) ]]; then
    echo "Error: -d <db>, -f <fasta>, and -o <outdir> are required when using -p (predict mode)"
    exit 1
fi

# -----------------------------
# Run pipeline
# -----------------------------

if [[ $makedb -eq 1 ]]; then
    echo "=== BUILDING DIAMOND DATABASE ==="
    $diamond makedb --in "$diamond_fasta" -d "$diamond_db" -p "$threads"
fi

if [[ $predict -eq 1 ]]; then
    echo "=== CHECKING FASTA HEADER FORMAT ==="
    python3 /argot25/src/check_fasta.py -f "$source_fasta" -o "${source_fasta}.clean"
    mv "${source_fasta}.clean" "$source_fasta"

    echo "=== RUNNING DIAMOND & ARGOT PIPELINE ==="
    mkdir -p /wdir/data/input /wdir/data/output "$results"

    echo "Running DIAMOND..."
    $diamond blastp -d "$diamond_db" -q "$source_fasta" -o /wdir/data/output/diamond_raw.blastp -f 6 -b 5 -c 1 -k 1000 -p "$threads"

    echo "Cleaning DIAMOND output..."
    if [ -f /wdir/data/output/diamond_clean.blastp ]
    then
        rm /wdir/data/output/diamond_clean.blastp
    fi
    python3 /argot25/src/clean_blastp.py -i /wdir/data/output/diamond_raw.blastp -o /wdir/data/output/diamond_clean.blastp

    echo "Creating Argot input..."
    python3 /argot25/src/new_blastp_to_argot_inp.py -b /wdir/data/output/diamond_clean.blastp -m localhost -d ARGOT_NEW -c annots -o /wdir/data/input/argot_in.txt

    echo "Running Argot..."
    $argot -i /wdir/data/input/argot_in.txt -s localhost -d ARGOT_NEW -o /wdir/data/output/argot_out.txt -g /wdir/support_files/go.owl -c goafreq

    echo "Converting to CAFA format..."
    python3 /argot25/src/in-cafa_format.py -i /wdir/data/output/argot_out.txt -v Argot3 -o /wdir/data/output/ -f temporary

    echo "Propagating GO terms..."
    mv /wdir/data/output/temporary_argot_out_in_cafa.txt "$results/predictions_raw.tsv"
    python3 /argot25/src/propagate.py -i "$results/predictions_raw.tsv" -o "$results/predictions_prop.tsv" -g /argot25/support_files/go.owl -p

    python3 /argot25/src/format_out.py -i "$results/predictions_raw.tsv" -o "$results/predictions_raw.tsv.final" -g /argot25/support_files/go.owl
    python3 /argot25/src/format_out.py -i "$results/predictions_prop.tsv" -o "$results/predictions_prop.tsv.final" -g /argot25/support_files/go.owl
    mv "$results/predictions_raw.tsv.final" "$results/predictions_raw.tsv"
    mv "$results/predictions_prop.tsv.final" "$results/predictions_prop.tsv"
fi

echo "=== DONE ==="
