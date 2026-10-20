#!/usr/bin/env bash
# Downloads the llama.cpp runtime and the weights into /data once, then serves the API.
# Configuration comes from environment variables (see ../.env.example).
set -euo pipefail

cd /data
mkdir -p models runtimes

size="${RIZZO_SIZE:-4b}"
quant="${RIZZO_QUANT:-q8_0}"
weights="${RIZZO_WEIGHTS:-flow}"
runtime="${RIZZO_RUNTIME:-cpu}"

# `rizzo download` is idempotent, but verifying the 4.4 GB GGUF hash costs ~10 s at every
# start, so a stamp per configuration skips it. RIZZO_FORCE_DOWNLOAD=1 re-checks everything.
stamp="/data/.ready-${size}-${quant}-${weights}-${runtime}"
if [[ ! -f "$stamp" || "${RIZZO_FORCE_DOWNLOAD:-0}" == "1" ]]; then
  echo "rizzo-flow: downloading llama.cpp ($runtime) + $size $quant ($weights) into /data" >&2
  rizzo download --size "$size" --quant "$quant" --weights "$weights" --runtime "$runtime"
  touch "$stamp"
fi

args=(
  serve
  --host 0.0.0.0
  --port "${RIZZO_INTERNAL_PORT:-8017}"
  --size "$size"
  --quant "$quant"
  --weights "$weights"
  --device "${RIZZO_DEVICE:-cpu}"
  --ctx "${RIZZO_CTX:-8192}"
  --batch-size "${RIZZO_BATCH_SIZE:-4}"
)
[[ -n "${RIZZO_THREADS:-}" ]] && args+=(--threads "$RIZZO_THREADS")
[[ -n "${RIZZO_KV_TYPE:-}" ]] && args+=(--kv-type "$RIZZO_KV_TYPE")
if [[ -n "${RIZZO_CALIBRATION:-}" && -f "${RIZZO_CALIBRATION}" ]]; then
  args+=(--calibration "$RIZZO_CALIBRATION")
fi

if [[ -n "${RIZZO_API_KEY:-}" ]]; then
  echo "rizzo-flow: Bearer auth enabled (RIZZO_API_KEY is set)" >&2
fi
echo "rizzo-flow: serving on http://0.0.0.0:${RIZZO_INTERNAL_PORT:-8017} (device: ${RIZZO_DEVICE:-cpu})" >&2

exec rizzo "${args[@]}"
