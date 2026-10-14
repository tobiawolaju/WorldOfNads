# Multi-stage build for the Rust room server.
#
#   docker build -t wons-room-server backend-rust
#   docker run --rm -p 8080:8080 wons-room-server
#
# The final image is a tiny Debian runtime with just the static-ish binary.
# Swap the runtime base for `gcr.io/distroless/cc-debian12` if you prefer.

FROM rust:1-slim AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock* ./
# Cache dependency builds: a stub main that pulls the same deps.
RUN mkdir src && echo 'fn main() {}' > src/main.rs && cargo build --release && rm -rf src
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim AS runtime
RUN useradd --create-home --uid 10001 app
COPY --from=builder /app/target/release/room-server /usr/local/bin/room-server
USER app
ENV RUST_LOG=room_server=info
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/room-server"]
