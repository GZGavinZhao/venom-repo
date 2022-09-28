#!/bin/bash

set -eo pipefail

upload() {
	echo "The following packages will get uploaded:"
	fd . -u -e stone "$1"
	fd . -u -e stone "$1" --exec aliyun oss cp {} oss://venom-testing/{}
}

delete() {
	echo "Deleting packages in oss://venom-testing/${1}"
	aliyun oss rm -r oss://venom-testing/"$1"
}

check() {
	aliyun oss ls oss://venom-testing
}

build() {
	# boulder's return code is STILL 0 even if build fails!
	sudo boulder build -p venom-x86_64
}

find-pkg() {
	fd -u -e stone "$1"
}

build-pkg() {
	pushd "$1" || exit 1
	build
	popd || exit 1

	upload "$1"
}

clean() {
	echo "Cleaning $1"
	git clean -f -x -e .env -e "*tfstate*" "$1"
}

rebuild() {
	if [[ ! -f "${1}/stone.yml" ]]; then
		echo "No stone.yml found in ${1}!"
		exit 1
	fi

	clean "$1"

	echo "Rebuilding package ${1}"
	pushd "$1" || exit 1
	build
	popd || exit 1

	delete "$1"
	upload "$1"
}

$1 $2
