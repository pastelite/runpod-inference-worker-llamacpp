# =============================================================================
# Build arguments for preloading a GGUF model at build time.
#
#   HF_MODEL_URL      - Direct download URL for the GGUF file
#                       (e.g. from Hugging Face's "resolve/main" link)
#   MODEL_FILENAME    - File name to save the model as under /work/models/
#   LLAMA_SERVER_ARGS - Default llama-server arguments (fallback when
#                       LLAMA_SERVER_CMD_ARGS is not set at runtime)
#
# When both HF_MODEL_URL and MODEL_FILENAME are set, the model is downloaded
# during the build and PRELOADED_MODEL is set so start.sh can find it.
# =============================================================================
ARG HF_MODEL_URL=""
ARG MODEL_FILENAME=""
ARG LLAMA_SERVER_ARGS="--ctx-size 4096 -ngl 999 --flash-attn"

# Use an official ggml-org/llama.cpp image as the base image
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ENV PYTHONUNBUFFERED=1

# Set up the working directory
WORKDIR /

RUN apt-get update --yes --quiet && DEBIAN_FRONTEND=noninteractive apt-get install --yes --quiet --no-install-recommends \
    software-properties-common \
    gpg-agent \
    build-essential apt-utils \
    && apt-get install --reinstall ca-certificates \
    && add-apt-repository --yes ppa:deadsnakes/ppa && apt update --yes --quiet \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --quiet --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3.11-distutils \
    python3.11-lib2to3 \
    python3.11-gdbm \
    python3.11-tk \
    bash \
    curl && \
    ln -s /usr/bin/python3.11 /usr/bin/python && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /work

# Add ./src as /work
ADD ./src /work

# Install runpod and its dependencies
RUN pip install -r ./requirements.txt && chmod +x /work/start.sh

# ---------------------------------------------------------------------------
# Preload a GGUF model at build time (if HF_MODEL_URL is provided).
# The model is stored in /work/models/ and PRELOADED_MODEL is set so
# start.sh can automatically pick it up at runtime.
#
# At runtime you can still override LLAMA_SERVER_CMD_ARGS to use a
# different model or the -hf flag for on-the-fly HuggingFace downloads.
# ---------------------------------------------------------------------------
ARG HF_MODEL_URL
ARG MODEL_FILENAME
ARG LLAMA_SERVER_ARGS

RUN mkdir -p /work/models && \
    if [ -n "$HF_MODEL_URL" ] && [ -n "$MODEL_FILENAME" ]; then \
        echo "============================================================" && \
        echo " Preloading model from:" && \
        echo "   $HF_MODEL_URL" && \
        echo " Saving to: /work/models/$MODEL_FILENAME" && \
        echo "============================================================" && \
        curl -L -o "/work/models/$MODEL_FILENAME" "$HF_MODEL_URL" && \
        echo "============================================================" && \
        echo " Model preloaded successfully:" && \
        echo "   /work/models/$MODEL_FILENAME" && \
        ls -lh "/work/models/$MODEL_FILENAME" && \
        echo "============================================================" ; \
    else \
        echo "No HF_MODEL_URL provided — skipping model preload."; \
    fi

# Set PRELOADED_MODEL so start.sh can auto-detect the baked-in model.
# If no model was preloaded (MODEL_FILENAME empty), this will point to
# /work/models/ (a directory), and start.sh's -f check will skip it.
ENV PRELOADED_MODEL="/work/models/${MODEL_FILENAME}"

# Persist the build-time LLAMA_SERVER_ARGS as a runtime env var so
# start.sh can use it as the fallback default for LLAMA_SERVER_CMD_ARGS.
ENV LLAMA_SERVER_ARGS=${LLAMA_SERVER_ARGS}

# Set the entrypoint
ENTRYPOINT ["/bin/sh", "-c", "/work/start.sh"]
