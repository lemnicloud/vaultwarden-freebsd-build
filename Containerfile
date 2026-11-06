ARG VERSION=1.37.4

FROM docker.io/freebsd/freebsd-toolchain:15.1 AS builder

ARG VERSION

ENV ASSUME_ALWAYS_YES=yes \
    CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:${PATH}

# gmake and perl5 for the vendored OpenSSL build, postgresql18-client for libpq
RUN pkg install -y gmake pkgconf perl5 postgresql18-client

RUN set -ex; \
      fetch -o /tmp/src.tar.gz https://github.com/dani-garcia/vaultwarden/archive/refs/tags/${VERSION}.tar.gz; \
      mkdir -p /src; \
      tar -xzf /tmp/src.tar.gz -C /src --strip-components=1

# Rust version comes from upstream's rust-toolchain.toml
RUN set -ex; \
      fetch -o /tmp/rustup-init https://static.rust-lang.org/rustup/dist/x86_64-unknown-freebsd/rustup-init; \
      fetch -o /tmp/rustup-init.sha256 https://static.rust-lang.org/rustup/dist/x86_64-unknown-freebsd/rustup-init.sha256; \
      sha256 -c "$(cut -d' ' -f1 /tmp/rustup-init.sha256)" /tmp/rustup-init; \
      chmod 755 /tmp/rustup-init; \
      rust_version=$(sed -nE 's/^channel = "([^"]+)"/\1/p' /src/rust-toolchain.toml); \
      test -n "${rust_version}"; \
      /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "${rust_version}"

# RUSTUP_TOOLCHAIN overrides rust-toolchain.toml, so its rustfmt/clippy components aren't fetched.
# openssl-src runs `make`, which has to be GNU make.
WORKDIR /src
RUN set -ex; \
      export RUSTUP_TOOLCHAIN=$(sed -nE 's/^channel = "([^"]+)"/\1/p' rust-toolchain.toml); \
      mkdir -p /tmp/makebin /app; \
      ln -sf /usr/local/bin/gmake /tmp/makebin/make; \
      PATH="/tmp/makebin:${PATH}" MAKE=gmake VW_VERSION=${VERSION} \
        cargo build --locked --release --features sqlite,postgresql,vendored_openssl; \
      cp target/release/vaultwarden /app/vaultwarden

# Web vault version comes from upstream's docker/DockerSettings.yaml
RUN set -ex; \
      web_vault_version=$(sed -nE 's/^vault_version: "([^"]+)"/\1/p' docker/DockerSettings.yaml); \
      test -n "${web_vault_version}"; \
      url=https://github.com/dani-garcia/bw_web_builds/releases/download/${web_vault_version}; \
      fetch -o /tmp/bw_web.tar.gz ${url}/bw_web_${web_vault_version}.tar.gz; \
      fetch -o /tmp/bw_web.sha256sums.txt ${url}/sha256sums.txt; \
      expected=$(grep " bw_web_${web_vault_version}.tar.gz\$" /tmp/bw_web.sha256sums.txt | cut -d' ' -f1); \
      test -n "${expected}"; \
      sha256 -c "${expected}" /tmp/bw_web.tar.gz; \
      tar -xzf /tmp/bw_web.tar.gz -C /app

# podman build --target output -o type=local,dest=./out
FROM scratch AS output
COPY --from=builder /app/ /
