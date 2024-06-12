#!/usr/bin/env bash

echo "*****************************************"
echo "*        Download GCC & Binutils        *"
echo "*****************************************"

MASTER=false
GCC10=false
for ARGS in $@; do
    case $ARGS in
    master)
        MASTER=true GCC10=false
        ;;
    gcc10)
        GCC10=true MASTER=false
        ;;
    *)
        GCC10=false MASTER=false
        ;;
    esac
done
export MASTER GCC10

download() {
    if ${MASTER}; then
        git clone --depth=1 -b master git://sourceware.org/git/binutils-gdb.git binutils
        git clone --depth=1 -b master git://gcc.gnu.org/git/gcc.git gcc
        git clone --depth=1 -b dev https://github.com/facebook/zstd zstd
    elif ${GCC10}; then
        git clone --depth=1 -b binutils-2_42-branch https://github.com/Diaz1401/binutils-gdb.git binutils
        git clone --depth=1 -b releases/gcc-10 https://github.com/Diaz1401/gcc gcc
        git clone --depth=1 -b v1.5.6 https://github.com/facebook/zstd zstd
    else
        git clone --depth=1 -b binutils-2_42-branch https://github.com/Diaz1401/binutils-gdb.git binutils
        git clone --depth=1 -b releases/gcc-13 https://github.com/Diaz1401/gcc gcc
        git clone --depth=1 -b v1.5.6 https://github.com/facebook/zstd zstd
    fi
    sed -i '/^development=/s/true/false/' binutils/bfd/development.sh
    cd gcc
    ./contrib/download_prerequisites
    cd -
}

download
