FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential python3-venv python3-pip python3-tomli ninja-build \
    pkg-config libglib2.0-dev libpixman-1-dev zlib1g-dev libfdt-dev \
    git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
