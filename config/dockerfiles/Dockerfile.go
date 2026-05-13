# syntax=docker/dockerfile:1

# Production Go application template:
# - build on the reviewed Debian/Trixie Go image
# - run the compiled static binary on distroless as a nonroot user
ARG DEV_GO_IMAGE
ARG DEV_DISTROLESS_STATIC_IMAGE

FROM ${DEV_GO_IMAGE:-golang:1.26.3-trixie} AS dev

WORKDIR /workspace
ENV CGO_ENABLED=0
COPY . .

RUN cd src && \
    go test ./... && \
    go build -trimpath -buildvcs=false -ldflags="-s -w" -o /out/app ./cmd/app

FROM ${DEV_DISTROLESS_STATIC_IMAGE:-gcr.io/distroless/static-debian13:nonroot} AS runtime

WORKDIR /
COPY --from=dev /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
