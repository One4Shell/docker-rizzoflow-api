# Rizzo Flow API — llama.cpp build (no MLX), CPU or Vulkan GPU.
#
# The source is cloned at a pinned commit, so the build is reproducible and this folder stays
# a handful of files. The llama.cpp binaries (30 MB) and the GGUF weights (~4.4 GB) are fetched
# by the entrypoint into /data on first start, so the image stays small and the heavy files
# survive `down`, rebuilds and `prune`.
#
# bookworm (glibc 2.36) runs the official ubuntu-x64 llama.cpp build (max GLIBC_2.34).
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

# Bump with: make update
ARG RIZZO_REPO=https://github.com/Rizzo-AI-Academy/rizzo-flow
ARG RIZZO_COMMIT=b9ba007ee4d2928bbab5b1d8bfe9009c3696b6de

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    HF_HOME=/data/hf

# git+ca-certificates: fetch the pinned source over HTTPS.
# libvulkan1 + Mesa: the `vulkan` llama.cpp plug-in dlopens libvulkan.so.1 and the host GPU's
#   ICD (RADV for AMD, ANV for Intel). Unused when RIZZO_RUNTIME=cpu; adds ~40 MB.
# libgomp1: hard dependency of libggml-base.so.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates git libgomp1 libvulkan1 mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git init -q . \
    && git remote add origin "$RIZZO_REPO" \
    && git fetch -q --depth 1 origin "$RIZZO_COMMIT" \
    && git checkout -q FETCH_HEAD \
    && rm -rf .git

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

ENV PATH="/app/.venv/bin:$PATH"

COPY docker/entrypoint.sh /usr/local/bin/rizzo-entrypoint
RUN chmod 0755 /usr/local/bin/rizzo-entrypoint

# Everything writable lives on the volume: models/, runtimes/, hf/.
WORKDIR /data
EXPOSE 8017

ENTRYPOINT ["/usr/local/bin/rizzo-entrypoint"]
CMD []
