# Cross-build image for linux/arm64 with glibc 2.35: the binary needs nothing newer, so it
# runs on any newer Linux (Ubuntu 22.04+, Debian 12+) and in the deploy image.
FROM --platform=linux/arm64 ubuntu:22.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends clang-14 libc6-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
