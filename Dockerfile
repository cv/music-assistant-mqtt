# The image: the program as one static binary (musl, cross-compiled by zig for the target) and
# nothing else, about 1 MB. Bend emits the C first (bend mam.bend -o out/mam.c, as CI does); the
# build stage runs on the build machine, so no emulation is needed.
#   bend mam.bend -o out/mam.c && docker build -t music-assistant-mqtt .
FROM --platform=$BUILDPLATFORM alpine:3.22 AS build
ARG TARGETARCH
RUN apk add --no-cache zig
WORKDIR /src
COPY out/mam.c .
RUN case "$TARGETARCH" in \
      arm64) t=aarch64 ;; \
      amd64) t=x86_64 ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && ZIG_GLOBAL_CACHE_DIR=/tmp/zig ZIG_LOCAL_CACHE_DIR=/tmp/zig \
       zig cc -target "$t-linux-musl" -O3 -static -s -o /mam mam.c -lpthread -lm

FROM scratch
COPY --from=build /mam /mam
USER 65532:65532
ENTRYPOINT ["/mam"]
CMD ["/etc/music-assistant-mqtt.conf"]
