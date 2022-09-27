FROM debian:bookworm-slim as runtime

RUN apt update && apt install -yq --no-install-recommends ca-certificates \
		libphobos2-ldc-shared100 \
		xxhash \
		libcurl4 \
		libzstd1 \
		liblmdb0 \
		zlib1g \
		&& apt clean \
		&& rm -rf /var/cache/apt/archives /var/lib/apt/lists/*



FROM runtime as devel

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
ENV DFLAGS="-L-lz"

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
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/boulder
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss
RUN git clone --shallow-submodules --recursive https://github.com/serpent-os/moss-container



FROM devel as moss-devel

WORKDIR /serpent/moss
ENV DESTDIR=/serpent/destdir

RUN meson build --prefix=/usr --buildtype=release \
	&& ninja -C build -j4 \
	&& ninja -C build install



FROM moss-devel as moss-container-devel

WORKDIR /serpent/moss-container

RUN meson build --prefix=/usr --buildtype=release \
	&& ninja -C build -j4 \
	&& ninja -C build install



FROM moss-container-devel as boulder-devel

WORKDIR /serpent/boulder

RUN meson build --prefix=/usr --buildtype=release \
	&& ninja -C build -j4 \
	&& ninja -C build install



FROM golang:1.19-bullseye as server

RUN mkdir -p /server/fc
WORKDIR /server

COPY go.mod go.sum .
COPY fc fc
ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go build -o server ./fc/server



FROM runtime as moss

COPY --from=moss-devel /serpent/moss/build/moss /usr/bin/moss
RUN apt clean && rm -rf /var/cache/apt/archives /var/lib/apt/lists/*
CMD ["/bin/bash"]



FROM moss as fc-server

COPY --from=server /server/server /server/server
RUN apt clean && rm -rf /var/cache/apt/archives /var/lib/apt/lists/*
EXPOSE 9000
CMD ["/server/server"]



FROM runtime as boulder

COPY --from=boulder-devel /serpent/destdir /
