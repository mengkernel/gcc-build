#!/usr/bin/env bash

echo "*****************************************"
echo "*        Download GCC & Binutils        *"
echo "*****************************************"

export IS_MASTER="${1}"

download() {
    if [ "${IS_MASTER}" == "master" ]; then
        git clone -b master --depth=1 git://sourceware.org/git/binutils-gdb.git binutils
        git clone -b master --depth=1 git://gcc.gnu.org/git/gcc.git gcc
        git clone -b dev https://github.com/facebook/zstd zstd
    else
        git clone --depth=1 https://github.com/Diaz1401/binutils-gdb.git binutils
        git clone --depth=1 https://github.com/Diaz1401/gcc gcc
        git clone -b v1.5.5 https://github.com/facebook/zstd zstd
    fi
    sed -i '/^development=/s/true/false/' binutils/bfd/development.sh
    cd gcc
    ./contrib/download_prerequisites
    cd ..
}

download
