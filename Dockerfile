# syntax=docker/dockerfile:1

FROM nixos/nix:latest AS builder

RUN mkdir -p /etc/nix && \
    printf "experimental-features = nix-command flakes\nsandbox = true\nsandbox-fallback = false\n" >> /etc/nix/nix.conf

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true

# Pin an exact commit or tag from zhaofengli/attic — not a branch
ARG ATTIC_REF=7a19204df10d606c5070e6bb72615c3461900c05

RUN git clone https://github.com/zhaofengli/attic.git /src/attic && \
    cd /src/attic && \
    git checkout "${ATTIC_REF}" && \
    git log -1 --format="Built from attic commit: %H (%ci)"

WORKDIR /src/attic

# Confirm what this actually produces before trusting it
RUN nix flake show . 2>&1 | tee /tmp/flake-outputs.txt

RUN nix build --no-sandbox --print-out-paths .#attic -o /result

# Sanity check the binaries actually exist in the built output
RUN ls -la /result/bin/

# Collect the full runtime closure (binary + all its transitive deps)
RUN mkdir -p /rootfs/nix/store /rootfs/bin && \
    for p in $(nix-store -qR /result); do \
      cp -a "$p" /rootfs/nix/store/; \
    done && \
    for bin in atticd atticadm attic; do \
      if [ -e "$(readlink -f /result)/bin/$bin" ]; then \
        ln -s "$(readlink -f /result)/bin/$bin" "/rootfs/bin/$bin"; \
      fi; \
    done && \
    ls -la /rootfs/bin/

FROM scratch
COPY --from=builder /rootfs /
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

EXPOSE 8080
ENTRYPOINT ["/bin/atticd"]
