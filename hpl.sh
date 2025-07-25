#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "$( readlink -f "${BASH_SOURCE[0]}" )" )" &> /dev/null && pwd )
XHPL="$SCRIPT_DIR/xhpl"


if [[ -r "$SCRIPT_DIR/hpc-benchmarks-gpu-env.sh" ]]; then
  source "$SCRIPT_DIR/hpc-benchmarks-gpu-env.sh"
fi


# FIXME - workaround for Singularity
export LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

export UCX_WARN_UNUSED_ENV_VARS=${UCX_WARN_UNUSED_ENV_VARS:-n}

export OMP_PROC_BIND=${OMP_PROC_BIND:-TRUE}
export OMP_PLACES=${OMP_PLACES:-sockets}

export NVSHMEM_DISABLE_NCCL=${NVSHMEM_DISABLE_NCCL:-1}
export NVSHMEM_DISABLE_CUDA_VMM=${NVSHMEM_DISABLE_CUDA_VMM:-0}
export NVSHMEM_SYMMETRIC_SIZE=${NVSHMEM_SYMMETRIC_SIZE:-2.7G}

export NVSHMEM_DISABLE_GDRCOPY=${NVSHMEM_DISABLE_GDRCOPY:-1}
export CUDA_MODULE_LOADING=${CUDA_MODULE_LOADING:-EAGER}

# NCCL >= 2.22 allows dynamic runtime connection, which can allocate more device 
# memory during the first communication operation. Disable this so we don't go 
# OOM during a HPL run
export NCCL_RUNTIME_CONNECT=${NCCL_RUNTIME_CONNECT:-0}

# FIXME - workaround for HPC-X 2.18
export UCC_LOG_LEVEL=error

# HPL specific
# Default values are used. See `TUNING` file

usage() {
  echo ""
  echo "$(basename "$0") [OPTION]"
  echo "    --dat <string>                path to HPL.dat"
  echo "    --cuda-compat                 manually enable CUDA forward compatibility"
  echo "    --no-multinode                enable flags for no-multinode (no-network) execution"
  echo "    --gpu-affinity <string>       colon separated list of gpu indices"
  echo "    --cpu-affinity <string>       colon separated list of cpu index ranges"  
  echo "    --mem-affinity <string>       colon separated list of memory indices"
  echo "    --ucx-affinity <string>       colon separated list of UCX devices"
  echo "    --ucx-tls <string>            UCX transport to use"
  echo "    --exec-name <string>          HPL executable file"
  echo ""
}

info() {
  local msg=$*
  echo -e "INFO: ${msg}"
}

warning() {
  local msg=$*
  echo -e "WARNING: ${msg}"
}

error() {
  local msg=$*
  echo -e "ERROR: ${msg}"
  exit 1
}

 
# split the affinity string, e.g., '0:2:4:6' into an array,
# e.g., map[0]=0, map[1]=2, ...  The array index is the MPI rank.
read_gpu_affinity_map() {
    local affinity_string=$1
    readarray -t GPU_AFFINITY_MAP <<<"$(tr ':' '\n'<<<"$affinity_string")"
}

# split the affinity string, e.g., '0:2:4:6' into an array,
# e.g., map[0]=0, map[1]=2, ...  The array index is the MPI rank.
read_net_affinity_map() {
    local affinity_string=$1
    readarray -t NET_AFFINITY_MAP <<<"$(tr ':' '\n'<<<"$affinity_string")"
}

# split the affinity string, e.g., '0:2:4:6' into an array,
# e.g., map[0]=0, map[1]=2, ...  The array index is the MPI rank.
read_mem_affinity_map() {
    local affinity_string=$1
    readarray -t MEM_AFFINITY_MAP <<<"$(tr ':' '\n'<<<"$affinity_string")"
}

# split the affinity string, e.g., '0:2:4:6' into an array,
# e.g., map[0]=0, map[1]=2, ...  The array index is the MPI rank.
read_cpu_affinity_map() {
    local affinity_string=$1
    readarray -t CPU_AFFINITY_MAP <<<"$(tr ':' '\n'<<<"$affinity_string")"
}

# set PMIx client configuration to match the server
# enroot already handles this, so only do this under singularity
# https://github.com/NVIDIA/enroot/blob/master/conf/hooks/extra/50-slurm-pmi.sh
set_pmix() {
    if [ -d /.singularity.d ]; then
        if [ -n "${PMIX_PTL_MODULE-}" ] && [ -z "${PMIX_MCA_ptl-}" ]; then
            export PMIX_MCA_ptl=${PMIX_PTL_MODULE}
        fi
        if [ -n "${PMIX_SECURITY_MODE-}" ] && [ -z "${PMIX_MCA_psec-}" ]; then
            export PMIX_MCA_psec=${PMIX_SECURITY_MODE}
        fi
        if [ -n "${PMIX_GDS_MODULE-}" ] && [ -z "${PMIX_MCA_gds-}" ]; then
            export PMIX_MCA_gds=${PMIX_GDS_MODULE}
        fi
    fi
}

### main script starts here

# Read command line arguments
while [ "$1" != "" ]; do
  case $1 in
   --cuda-compat )
      export LD_LIBRARY_PATH="/usr/local/cuda/compat:$LD_LIBRARY_PATH"
      ;;
    --no-multinode )
      export NVSHMEM_REMOTE_TRANSPORT=none
      ;;
    --dat )
      if [ -n "$2" ]; then
        DAT="$2"
      else
        usage
        exit 1
      fi
      shift
      ;;
    --exec-name )
        XHPL=$2
        shift
        ;;
    --ucx-tls )
      if [ -n "$2" ]; then
        export UCX_TLS="$2"
      else
        usage
        exit 1
      fi
      shift
      ;;
    --ucx-affinity )
      if [ -n "$2" ]; then
        NET_AFFINITY="$2"
      else
        usage
        exit 1
      fi
      shift
      ;;
    --gpu-affinity )
      if [ -n "$2" ]; then
        GPU_AFFINITY="$2"
      else
        usage
        exit 1
      fi
      shift
      ;;
    --mem-affinity )
      if [ -n "$2" ]; then
        MEM_AFFINITY="$2"
      else
        usage
        exit 1
      fi
      shift
      ;;
    --cpu-affinity )
      if [ -n "$2" ]; then
        CPU_AFFINITY="$2"
      else
        usage
        exit 1
      fi
      shift
      ;;
  * )
    usage
    exit 1
  esac
  shift
done

# Setup PMIx, if using
if [[ -z "${SLURM_MPI_TYPE-}" || "${SLURM_MPI_TYPE}" == pmix* ]]; then
  set_pmix
fi

read_rank() {
  # Global rank
  if [ -n "${OMPI_COMM_WORLD_RANK}" ]; then
    RANK=${OMPI_COMM_WORLD_RANK}
  elif [ -n "${PMIX_RANK}" ]; then
    RANK=${PMIX_RANK}
  elif [ -n "${PMI_RANK}" ]; then
    RANK=${PMI_RANK}
  elif [ -n "${SLURM_PROCID}" ]; then
    RANK=${SLURM_PROCID}
  else
    warning "could not determine rank"
  fi

  # Node local rank
  if [ -n "${OMPI_COMM_WORLD_LOCAL_RANK}" ]; then
    LOCAL_RANK=${OMPI_COMM_WORLD_LOCAL_RANK}
  elif [ -n "${SLURM_LOCALID}" ]; then
    LOCAL_RANK=${SLURM_LOCALID}
  elif [ -n "${MPI_LOCALRANKID}" ]; then
    LOCAL_RANK=${MPI_LOCALRANKID}
  else
    error "could not determine local rank"
  fi
}

if [[ -n "${NET_AFFINITY}" ]]; then
  read_rank
  read_net_affinity_map $NET_AFFINITY
  NET=${NET_AFFINITY_MAP[$LOCAL_RANK]}
  if [ -n "${NET}" ]; then
    export UCX_NET_DEVICES="$NET:1"
  fi
fi

if [[ -n "${GPU_AFFINITY}" ]]; then
  read_rank
  read_gpu_affinity_map $GPU_AFFINITY
  GPU=${GPU_AFFINITY_MAP[$LOCAL_RANK]}
  export HPL_VISIBLE_DEVICES=${GPU}
fi

if [[ -n "${MEM_AFFINITY}" ]]; then
  read_rank
  read_mem_affinity_map $MEM_AFFINITY
  MEM=${MEM_AFFINITY_MAP[$LOCAL_RANK]}
  MEMBIND="--membind=${MEM}"
fi

if [[ -n "${CPU_AFFINITY}" ]]; then
  read_rank
  read_cpu_affinity_map $CPU_AFFINITY
  CPU=${CPU_AFFINITY_MAP[$LOCAL_RANK]}
  CPUBIND="--physcpubind=${CPU}"
fi

if [ -n "${MEMBIND}" ] || [ -n "${CPUBIND}" ]; then
  NUMCMD="numactl "
fi

if [ -z "$DAT" ]; then
  error "DAT file not provided"
fi

# if [ $LOCAL_RANK -eq 0 ]; then
#   sudo nvidia-smi -lgc ${GPU_CLOCK}
# fi

${NUMCMD} ${CPUBIND} ${MEMBIND} ${XHPL} ${DAT}
