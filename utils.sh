#!/bin/bash

upload() {
	fd . -I -e stone $1 --exec aliyun oss cp {} oss://venom-testing/{}
}

check() {
	aliyun oss ls oss://venom-testing
}

build() {
	sudo boulder build -p venom-x86_64
}

find-pkg() {
	fd -I -e stone $1
}
