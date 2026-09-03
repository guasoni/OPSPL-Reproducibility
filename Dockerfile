# syntax=docker/dockerfile:1

# The multi-platform manifest digest fixes the exact Rocker R 4.3.2 base image.
FROM rocker/r-ver:4.3.2@sha256:4e32addfc4da3e660f6e0d05ce5e43d3eceb9db58a60b9a142e0dde9a654ead1

LABEL org.opencontainers.image.title="Option Portfolio Selection reproducibility environment" \
      org.opencontainers.image.description="R 4.3.2 execution environment for the JEF reproducibility package" \
      org.opencontainers.image.source="https://github.com/guasoni/OPSPL-Reproducibility"

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        gfortran \
        git \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /project
CMD ["Rscript", "reproduce.R", "--help"]
