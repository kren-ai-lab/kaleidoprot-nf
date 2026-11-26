# Runtime image of kpnf, built from this directory at a pipeline release tag.
FROM python:3.15-slim

LABEL org.opencontainers.image.source="https://github.com/kren-ai-lab/kaleidoprot-nf" \
      org.opencontainers.image.description="kpnf: glue operations for the kaleidoprot-nf pipeline" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update \
    && apt-get install -y --no-install-recommends procps \
    && rm -rf /var/lib/apt/lists/*

COPY . /tmp/kpnf
RUN pip install --no-cache-dir /tmp/kpnf && rm -rf /tmp/kpnf
