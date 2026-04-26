#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
build_dir="${repo_root}/build"
bin_dir="${build_dir}/bin"
output_dir="${repo_root}/profile_txt"

num_keys="${NUM_KEYS:-1000000}"
num_experiments="${NUM_EXPERIMENTS:-1}"
exist_ratio="${EXIST_RATIO:-1.0}"

benchmarks=(
  "insert_find_bench"
  "insert_find_blink_bench"
)

common_args=(
  "--num-keys=${num_keys}"
  "--num-experiments=${num_experiments}"
  "--exist-ratio=${exist_ratio}"
  "--validate=false"
)

mkdir -p "${output_dir}"

if [[ ! -d "${bin_dir}" ]]; then
  echo "Missing build output directory: ${bin_dir}" >&2
  echo "Build first, for example:" >&2
  echo "  cmake -S ${repo_root} -B ${build_dir} -Dbuild_tests=OFF -Dbuild_benchmarks=ON" >&2
  echo "  cmake --build ${build_dir} -j" >&2
  exit 1
fi

if ! command -v ncu >/dev/null 2>&1; then
  echo "ncu not found in PATH" >&2
  exit 1
fi

if ! command -v nsys >/dev/null 2>&1; then
  echo "nsys not found in PATH" >&2
  exit 1
fi

for benchmark in "${benchmarks[@]}"; do
  exe="${bin_dir}/${benchmark}"
  if [[ ! -x "${exe}" ]]; then
    echo "Missing benchmark binary: ${exe}" >&2
    exit 1
  fi

  echo "Profiling ${benchmark}"

  ncu_txt="${output_dir}/${benchmark}_ncu.txt"
  nsys_txt="${output_dir}/${benchmark}_nsys.txt"
  nsys_base="${output_dir}/${benchmark}_nsys_tmp"

  {
    echo "Command: ncu --target-processes all --set launch --profile-from-start off ${exe} ${common_args[*]}"
    echo
    ncu --target-processes all \
        --set launch \
        --profile-from-start off \
        "${exe}" \
        "${common_args[@]}"
  } > "${ncu_txt}" 2>&1

  nsys profile \
      --trace=cuda,nvtx,osrt \
      --capture-range=cudaProfilerApi \
      --stop-on-range-end=true \
      --force-overwrite=true \
      -o "${nsys_base}" \
      "${exe}" \
      "${common_args[@]}" >/dev/null 2>&1

  {
    echo "Command: nsys stats ${nsys_base}.nsys-rep"
    echo
    nsys stats "${nsys_base}.nsys-rep"
  } > "${nsys_txt}" 2>&1

  rm -f "${nsys_base}.nsys-rep" "${nsys_base}.sqlite"
done

echo "Saved text reports in ${output_dir}"
