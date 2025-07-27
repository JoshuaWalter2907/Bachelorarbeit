#!/bin/bash
export LC_NUMERIC=C   # Fix locale-related decimal issues

# === Konfiguration ===

if [ -z "$1" ]; then
    echo "Please enter the problem Size. Example: ./plot.sh 40000"
    exit 1
fi

RUN_ID="$1"
CSV_FILE="${RUN_ID}_N_NO_NCCL.csv"

INTERVAL=1  # Logging Interval                 
UPS_NAME="eaton-ups"
UPS_IP="172.20.38.30"

FIELDS=(
    "ups.power"
    "ups.realpower"
    "input.frequency"
    "input.voltage"
    "output.frequency"
    "output.voltage"
    "output.current"
    "ups.load"
    "battery.runtime"
    "battery.charge"
    "ups.temperature"
)

# Create CSV Header if not available
if [ ! -f "$CSV_FILE" ]; then
    {
        echo -n "timestamp"
        for f in "${FIELDS[@]}"; do
            echo -n ",$f"
        done
        echo
    } > "$CSV_FILE"
fi

log_data() {
    local end_time=$1
    while [ "$(date +%s)" -lt "$end_time" ]; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        DATA=$(upsc "${UPS_NAME}@${UPS_IP}")
        LINE="$TIMESTAMP"
        for field in "${FIELDS[@]}"; do
            VAL=$(echo "$DATA" | grep "^$field:" | awk '{print $2}')
            LINE="$LINE,$VAL"
        done
        echo "$LINE" >> "$CSV_FILE"
        sleep $INTERVAL
    done
}

# --- 10 Seconds measurments before the Benchmark ---
PRE_END_TIME=$(( $(date +%s) + 10 ))
log_data "$PRE_END_TIME"

# --- Edit HPL file with the entered problem size ---
HPL_DAT_FILE="HPL-2GPUs.dat"
if [ -f "$HPL_DAT_FILE" ]; then
    sed -i -E "s/^([[:space:]]*)[0-9]+([[:space:]]+Ns)/\1$RUN_ID\2/" "$HPL_DAT_FILE"
else
    echo "Error: $HPL_DAT_FILE not found."
    exit 1
fi

# --- start benchmark ---
BENCHMARK_END_FILE="/tmp/benchmark_end_$RUN_ID"
rm -f "$BENCHMARK_END_FILE"

(
    HPL_OOC_MODE=1 mpirun -np 2 ./hpl.sh --dat "HPL-2GPUs.dat"
    touch "$BENCHMARK_END_FILE"
) &

# --- continue logging whilst Benchmark is running ---
while [ ! -f "$BENCHMARK_END_FILE" ]; do
    INTERVAL_END=$(( $(date +%s) + INTERVAL ))
    log_data "$INTERVAL_END"
done

# --- 10 measurement after the Benchmark is finished ---
POST_END_TIME=$(( $(date +%s) + 10 ))
log_data "$POST_END_TIME"

echo "Logging done. File: $CSV_FILE"

