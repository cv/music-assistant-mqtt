# The bridge's image: the linux/arm64 binary from tools/cross-build.sh (glibc 2.35 or newer) on a
# minimal base with glibc and nothing else (no shell). tools/deploy.sh builds it on the host.
FROM gcr.io/distroless/cc-debian12:nonroot
COPY mam /usr/local/bin/mam
ENTRYPOINT ["/usr/local/bin/mam"]
CMD ["/etc/music-assistant-mqtt.conf"]
