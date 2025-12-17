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
    echo "  -d <db>           DIAMOND database name DB.dmnd"
    echo "  -f <fasta>        Input FASTA file for DIAMOND/Argot"
    echo "  -o <outdir>       Output directory for results"
    echo "  -t <threads>      Number of threads (default: 1)"
    echo "  -h                Show this help message"
    echo
    echo "Example:"
    echo "  $0 -f query.fasta -d db/diamond_db -s source.fasta -o results -t 16"
    exit 1
}

# -----------------------------
# Parse command-line options
# -----------------------------
threads=1
diamond_db=""
source_fasta=""
results=""

while getopts ":d:f:o:t:h" opt; do
    case $opt in
        d) diamond_db=$OPTARG ;;
        f) source_fasta=$OPTARG ;;
        o) results=$OPTARG ;;
        t) threads=$OPTARG ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
    esac
done

# -----------------------------
# Check required arguments
# -----------------------------
if [[ -z "$diamond_db" || -z "$source_fasta" || -z "$results"  ]]; then
    echo "Error: -d <db>, -f <fasta>, and -o <outdir> are required arguments"
    exit 1
fi

# -----------------------------
# Run pipeline
# -----------------------------
src=/argot25/src
input=$results/data/input
output=$results/data/output
preds=$results/predictions
mkdir -p $input $output $preds

echo "=== CHECKING FASTA HEADER FORMAT ==="
python3 $src/check_fasta.py -f $source_fasta -o $input/proteins_list.fasta

echo "=== RUNNING DIAMOND & ARGOT PIPELINE ==="
$diamond blastp -d $diamond_db -q $input/proteins_list.fasta -o $output/diamond_raw.blastp -f 6 -b 5 -c 1 -k 1000 -p $threads

echo "Cleaning DIAMOND output..."
if [ -f $output/diamond_clean.blastp ]
then
    rm $output/diamond_clean.blastp
fi
python3 $src/clean_blastp.py -i $output/diamond_raw.blastp -o $output/diamond_clean.blastp

echo "Creating Argot input..."
python3 $src/new_blastp_to_argot_inp.py -b $output/diamond_clean.blastp -m localhost -d ARGOT_NEW -c annots -o $input/argot_in.txt

echo "Running Argot..."
$argot -i $input/argot_in.txt -s localhost -d ARGOT_NEW -o $output/argot_out.txt -g /argot25/support_files/go.owl -c goafreq

echo "Converting to CAFA format..."
python3 $src/in-cafa_format.py -i $output/argot_out.txt -v Argot3 -o $output/ -f temporary

echo "Propagating GO terms..."
mv $output/temporary_argot_out_in_cafa.txt $output/predictions_raw.tsv
python3 $src/propagate.py -i $output/predictions_raw.tsv -o $output/predictions_prop.tsv -g /argot25/support_files/go.owl -p

python3 $src/format_out.py -i $output/predictions_raw.tsv -o $preds/unpropagated.tsv -g /argot25/support_files/go.owl
python3 $src/format_out.py -i $output/predictions_prop.tsv -o $preds/propagated.tsv -g /argot25/support_files/go.owl

echo "=== DONE ==="
