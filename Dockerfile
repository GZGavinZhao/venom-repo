FROM debian:bookworm as build

RUN apt update && apt install -yq --no-install-recommends \
		build-essential \
		ca-certificates \
		cmake \
		pkg-config \
		clang \
		ldc \
		dub \
		libxxhash-dev \
		libcurl4-openssl-dev \
		meson \
		ninja-build \
		git \
		make \
		libzstd-dev \
		liblmdb-dev \
		zlib1g-dev

ENV CC=clang
ENV CXX=clang++

RUN mkdir /serpent
WORKDIR /serpent

# Fetch dependencies
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-config
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-core
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-db
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-deps
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-fetcher
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-format
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-vendor

# Fetch moss
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss
WORKDIR /serpent/moss

# Build moss. Use dub as meson struggles to build.
RUN dub build


FROM golang:1.19-bullseye as server

RUN mkdir -p /server/fc
WORKDIR /server

COPY go.mod go.sum .
COPY fc fc
ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go build -o server ./fc/server

FROM debian:bookworm-slim as final

RUN apt update && apt install -yq --no-install-recommends ca-certificates \
		libphobos2-ldc-shared100 \
		xxhash \
		libcurl4 \
		libzstd1 \
		liblmdb0 \
		zlib1g \
		&& apt clean \
		&& rm -rf /var/cache/apt/archives /var/lib/apt/lists/*
COPY --from=build /serpent/moss/bin/moss /usr/bin/moss
COPY --from=server /server/server /server/server
EXPOSE 9000
CMD ["/server/server"]
