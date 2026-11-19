# Runtime image of kpnf, built from this directory at a pipeline release tag.
# Built and pushed by .github/workflows/publish-kpnf-container.yml.
#   docker build -t kpnf:dev python/
FROM python:3.14-slim

LABEL org.opencontainers.image.source="https://github.com/kren-ai-lab/kaleidoprot-nf" \
      org.opencontainers.image.description="kpnf: glue operations for the kaleidoprot-nf pipeline" \
      org.opencontainers.image.licenses="MIT"

# procps: Nextflow reads task metrics with `ps` inside the container.
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps \
    && rm -rf /var/lib/apt/lists/*

COPY . /tmp/kpnf
RUN pip install --no-cache-dir /tmp/kpnf && rm -rf /tmp/kpnf
