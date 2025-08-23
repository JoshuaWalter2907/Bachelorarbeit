#!/bin/bash
export LC_NUMERIC=C 

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <ProblemSize> <CommMethod: NCCL|NVSHMEM>"
    echo "Example: $0 40000 NCCL"
    exit 1
fi

RUN_ID="$1"
COMM_METHOD=$(echo "$2" | tr '[:lower:]' '[:upper:]') 

if [[ "$COMM_METHOD" != "NCCL" && "$COMM_METHOD" != "NVSHMEM" ]]; then
    echo "Error: Communication method must be NCCL or NVSHMEM."
    exit 1
fi

CSV_FILE="${RUN_ID}_${COMM_METHOD}.csv"

INTERVAL=1
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

PRE_END_TIME=$(( $(date +%s) + 10 ))
log_data "$PRE_END_TIME"

HPL_DAT_FILE="HPL-2GPUs.dat"
if [ -f "$HPL_DAT_FILE" ]; then
    sed -i -E "s/^([[:space:]]*)[0-9]+([[:space:]]+Ns)/\1$RUN_ID\2/" "$HPL_DAT_FILE"
else
    echo "Error: $HPL_DAT_FILE not found."
    exit 1
fi

BENCHMARK_END_FILE="/tmp/benchmark_end_${RUN_ID}_${COMM_METHOD}"
rm -f "$BENCHMARK_END_FILE"

if [ "$COMM_METHOD" == "NVSHMEM" ]; then
    (
        HPL_OOC_MODE=1 HPL_P2P_AS_BCAST=4 HPL_USE_NVSHMEM=1 HPL_NVSHMEM_SWAP=0 \
        mpirun -np 2 ./hpl.sh --dat "HPL-2GPUs.dat"
        touch "$BENCHMARK_END_FILE"
    ) &
else
    (
        HPL_OOC_MODE=1 \
        mpirun -np 2 ./hpl.sh --dat "HPL-2GPUs.dat"
        touch "$BENCHMARK_END_FILE"
    ) &
fi

while [ ! -f "$BENCHMARK_END_FILE" ]; do
    INTERVAL_END=$(( $(date +%s) + INTERVAL ))
    log_data "$INTERVAL_END"
done

POST_END_TIME=$(( $(date +%s) + 10 ))
log_data "$POST_END_TIME"

echo "Logging done. File: $CSV_FILE"
