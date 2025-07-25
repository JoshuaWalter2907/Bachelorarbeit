#!/usr/bin/env bash

ENV_SCRIPT_DIR="$( cd -- "$( dirname -- "$( readlink -f "${BASH_SOURCE[0]}" )" )" &> /dev/null && pwd )"

export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/cuda${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ -z "${NCCL_PATH+x}" ]] && export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/nccl${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ -z "${NVSHMEM_PATH+x}" ]] && export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/nvshmem${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ -z "${NVPL_BLAS_PATH+x}" ]] && export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/nvpl_blas${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ -z "${NVPL_LAPACK_PATH+x}" ]] && export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/nvpl_lapack${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ -z "${NVPL_SPARSE_PATH+x}" ]] && export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/nvpl_sparse${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ -z "${OMP_PATH+x}" ]] && export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/omp${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ -z "${TCMALLOC_PATH+x}" ]] && export LD_LIBRARY_PATH="$ENV_SCRIPT_DIR/lib/tcmalloc${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

export OMPI_MCA_coll_hcoll_enable=0

