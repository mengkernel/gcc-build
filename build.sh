#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
# Author: Vaisakh Murali

echo "*****************************************"
echo "* Building Bare-Metal Bleeding Edge GCC *"
echo "*****************************************"

WORK_DIR="${PWD}"
NPROC="$(nproc --all)"
PREFIX="${WORK_DIR}/install"
PREFIX_PGO="${WORK_DIR}/pgo"
PROFILES="${PREFIX_PGO}/profiles"
mkdir -p profiles
OPT_FLAGS="-pipe -O3 -flto=${NPROC} -fipa-pta -fgraphite -fgraphite-identity -floop-nest-optimize -fno-semantic-interposition -ffunction-sections -fdata-sections -Wl,--gc-sections"
GEN_FLAGS="-fprofile-generate=${PROFILES}"
USE_FLAGS="-fprofile-use=${PROFILES} -fprofile-correction -fprofile-partial-training -Wno-error=coverage-mismatch"
BUILD_DATE="$(cat ${WORK_DIR}/gcc/gcc/DATESTAMP)"
BUILD_DAY="$(date "+%d %B %Y")"
BUILD_TAG="$(date +%Y%m%d-%H%M-%Z)"
TARGETS=(aarch64-linux-gnu) # x86_64-linux-gnu
HEAD_SCRIPT="$(git log -1 --oneline)"
HEAD_GCC="$(git --git-dir gcc/.git log -1 --oneline)"
HEAD_BINUTILS="$(git --git-dir binutils/.git log -1 --oneline)"
PKG_VERSION="CAT"
MASTER=false
FINAL=false
for ARGS in $@; do
    case $ARGS in
    master)
        MASTER=true
        ;;
    esac
done

export PKG_VERSION WORK_DIR NPROC PREFIX OPT_FLAGS \
    BUILD_DATE BUILD_DAY BUILD_TAG TARGETS HEAD_SCRIPT \
    HEAD_GCC HEAD_BINUTILS MASTER FINAL PROFILES \
    PREFIX_PGO GEN_FLAGS USE_FLAGS

send_info() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d "parse_mode=html" \
        -d text="${1}" >/dev/null 2>&1
}

send_file() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
        -F document=@"${1}" \
        -F chat_id="${CHAT_ID}" \
        -F "parse_mode=html" \
        -F caption="${2}" >/dev/null 2>&1
}

build_zstd() {
    #  send_info "<b>GitHub Action : </b><pre>Zstd build started . . .</pre>"
    mkdir ${WORK_DIR}/build-zstd
    cd ${WORK_DIR}/build-zstd
    cmake ${WORK_DIR}/zstd/build/cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}/zstd" |& tee -a build.log
    make -j${NPROC} |& tee -a build.log
    make install -j${NPROC} |& tee -a build.log

    # check Zstd build status
    if [ -f "${PREFIX}/zstd/bin/zstd" ]; then
        rm -rf ${WORK_DIR}/build-zstd
        #    send_info "<b>GitHub Action : </b><pre>Zstd build finished ! ! !</pre>"
        cd -
    else
        send_info "<b>GitHub Action : </b><pre>Zstd build failed ! ! !</pre>"
        send_file ./build.log "Zstd build.log"
        cd -
        exit 1
    fi
}

build_binutils() {
    CURENT_TARGET=${1}

    #  send_info "<b>GitHub Action : </b><pre>Binutils build started . . .</pre><b>Target : </b><pre>[${TARGET}]</pre>"

    if ${FINAL}; then
        rm -rf ${WORK_DIR}/build-binutils
    fi
    mkdir ${WORK_DIR}/build-binutils
    cd ${WORK_DIR}/build-binutils

    # Check compiler first
    gcc -v |& tee -a build.log
    ld -v |& tee -a build.log

    if ${FINAL}; then
        ADD="${USE_FLAGS}"
        PREFIX_ADD="${PREFIX}"
    else
        ADD="${GEN_FLAGS}"
        PREFIX_ADD="${PREFIX_PGO}"
    fi

    env CFLAGS="${OPT_FLAGS} ${ADD}" CXXFLAGS="${OPT_FLAGS} ${ADD}" \
        ../binutils/configure \
        --disable-compressed-debug-sections \
        --disable-docs \
        --disable-gdb \
        --disable-gold \
        --disable-gprofng \
        --disable-multilib \
        --disable-nls \
        --disable-shared \
        --enable-ld=default \
        --enable-plugins \
        --enable-threads \
        --enable-64-bit-bfd \
        --prefix=${PREFIX_ADD}/${CURENT_TARGET} \
        --target=${CURENT_TARGET} \
        --with-pkgversion="${PKG_VERSION} Binutils" \
        --with-sysroot \
        --with-system-zlib \
        --quiet |& tee -a build.log
    make -j${NPROC} |& tee -a build.log
    make install -j${NPROC} |& tee -a build.log
    # check Binutils build status
    if [ -f "${PREFIX_ADD}/${CURENT_TARGET}/bin/${CURENT_TARGET}-ld" ]; then
        #    send_info "<b>GitHub Action : </b><pre>Binutils build finished ! ! !</pre>"
        cd -
    else
        send_info "<b>GitHub Action : </b><pre>Binutils build failed ! ! !</pre>"
        send_file ./build.log "Binutils build.log"
        cd -
        exit 1
    fi
}

build_gcc() {
    #  send_info "<b>GitHub Action : </b><pre>GCC build started . . .</pre><b>Target : </b><pre>[${TARGET}]</pre>"

    CURENT_TARGET=${1}

    if ${FINAL}; then
        rm -rf ${WORK_DIR}/build-gcc
    fi
    mkdir ${WORK_DIR}/build-gcc
    cd ${WORK_DIR}/build-gcc

    # Check compiler first
    gcc -v |& tee -a build.log
    ld -v |& tee -a build.log

    case ${CURENT_TARGET} in
    x86_64*)
        EXTRA_CONF="--without-cuda-driver"
        ;;
    aarch64*)
        EXTRA_CONF="--enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419"
        ;;
    esac

    if ${FINAL}; then
        ADD="${USE_FLAGS}"
        PREFIX_ADD="${PREFIX}"
    else
        ADD="${GEN_FLAGS}"
        PREFIX_ADD="${PREFIX_PGO}"
    fi

    env CFLAGS="${OPT_FLAGS} ${ADD}" CXXFLAGS="${OPT_FLAGS} ${ADD}" \
        ../gcc/configure \
        --disable-bootstrap \
        --disable-checking \
        --disable-decimal-float \
        --disable-docs \
        --disable-gcov \
        --disable-libcc1 \
        --disable-libffi \
        --disable-libgomp \
        --disable-libquadmath \
        --disable-libsanitizer \
        --disable-libssp \
        --disable-libstdcxx-debug \
        --disable-libstdcxx-pch \
        --disable-libvtv \
        --disable-multilib \
        --disable-nls \
        --disable-shared \
        --enable-default-pie \
        --enable-default-ssp \
        --enable-gnu-indirect-function \
        --enable-languages=c,c++ \
        --enable-linux-futex \
        --enable-threads=posix \
        --prefix=${PREFIX_ADD}/${CURENT_TARGET} \
        --target=${CURENT_TARGET} \
        --with-gnu-as \
        --with-gnu-ld \
        --with-headers=/usr/include \
        --with-newlib \
        --with-pkgversion="${PKG_VERSION} GCC" \
        --with-sysroot \
        --with-system-zlib \
        --quiet ${EXTRA_CONF} |& tee -a build.log
    make all-gcc -j${NPROC} |& tee -a build.log
    make all-target-libgcc -j${NPROC} |& tee -a build.log
    make install-gcc -j${NPROC} |& tee -a build.log
    make install-target-libgcc -j${NPROC} |& tee -a build.log

    # check GCC build status
    if [ -f "${PREFIX_ADD}/${CURENT_TARGET}/bin/${CURENT_TARGET}-gcc" ]; then
        #    send_info "<b>GitHub Action : </b><pre>GCC build finished ! ! !</pre>"
        cd -
    else
        send_info "<b>GitHub Action : </b><pre>GCC build failed ! ! !</pre>"
        send_file ./build.log "GCC build.log"
        cd -
        exit 1
    fi
}

strip_binaries() {
    #  send_info "<b>GitHub Action : </b><pre>Strip binaries . . .</pre>"

    find install -type f -exec file {} \; >.file-idx

    for TARGET in ${TARGETS[@]}; do
        case ${TARGET} in
        x86_64*)
            grep "x86-64" .file-idx |
                grep "not strip" |
                tr ':' ' ' | awk '{print $1}' |
                while read -r file; do
                    strip -s "$file"
                done
            ;;
        aarch64*)
            cp -rf ${PREFIX}/${TARGET}/bin/${TARGET}-strip ./stripp-a64
            grep "ARM" .file-idx | grep "aarch64" |
                grep "not strip" |
                tr ':' ' ' | awk '{print $1}' |
                while read -r file; do
                    ./stripp-a64 -s "$file"
                done
            ;;
        arm*)
            cp -rf ${PREFIX}/${TARGET}/bin/${TARGET}-strip ./stripp-a32
            grep "ARM" .file-idx | grep "eabi" |
                grep "not strip" |
                tr ':' ' ' | awk '{print $1}' |
                while read -r file; do
                    ./stripp-a32 -s "$file"
                done
            ;;
        esac
    done

    # clean unused files
    find install -name *.cmake -delete
    find install -name *.la -delete
    find install -name *.a -delete
    rm -rf stripp-* .file-idx
}

git_push() {
    send_info "<b>GitHub Action : </b><pre>Release into GitHub . . .</pre>"

    # Use aarch64 target config
    GCC_CONFIG="$(${PREFIX}/${TARGETS[0]}/bin/${TARGETS[0]}-gcc -v 2>&1)"
    GCC_VERSION="$(${PREFIX}/${TARGETS[0]}/bin/${TARGETS[0]}-gcc --version | head -n1 | cut -d' ' -f4)"
    BINUTILS_VERSION="$(${PREFIX}/${TARGETS[0]}/bin/${TARGETS[0]}-ld --version | head -n1 | cut -d' ' -f5)"
    MESSAGE="GCC: ${GCC_VERSION}-${BUILD_DATE}, Binutils: ${BINUTILS_VERSION}"

    # symlink liblto_plugin.so
    cd ${PREFIX}/${TARGETS[0]}/lib/bfd-plugins
    ln -sr ../../libexec/gcc/${TARGETS[0]}/${GCC_VERSION}/liblto_plugin.so .
    cd -

    git config --global user.name github-actions[bot]
    git config --global user.email github-actions[bot]@users.noreply.github.com
    if ${MASTER}; then
        git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Mengkernel/gcc ${WORK_DIR}/gcc-repo -b main
    else
        git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Diaz1401/gcc-stable ${WORK_DIR}/gcc-repo -b main
    fi

    # Generate archive
    cd ${WORK_DIR}/gcc-repo
    cp -rf ${PREFIX}/* .
    tar -I"${PREFIX}/zstd/bin/zstd --ultra -22 -T0" -cf gcc.tar.zst *
    cat README |
        sed s/GCCVERSION/$(echo ${GCC_VERSION}-${BUILD_DATE})/g |
        sed s/BINUTILSVERSION/$(echo ${BINUTILS_VERSION})/g >README.md
    git commit --allow-empty -as \
        -m "${MESSAGE}" \
        -m "${GCC_CONFIG}"
    git push origin main
    hub release create -a gcc.tar.zst -m "${MESSAGE}" ${BUILD_TAG}
    cd -
}

kernel() {
    CURRENT_TARGET=${1}
    CONFIG=""
    ARCH=""

    send_info "<b>GitHub Action : </b><pre>Kernel build started . . .</pre>"

    # Symlink plugin
    cd ${PREFIX_PGO}/${CURRENT_TARGET}/lib/bfd-plugins
    ln -sr ../../libexec/gcc/${CURRENT_TARGET}/${GCC_VERSION}/liblto_plugin.so .
    cd -

    cd kernel
    rm -rf out

    case ${CURENT_TARGET} in
    x86_64*)
        ARCH=x86
        CONFIG=defconfig
        git fetch --depth=1 origin 115c8415cabae300a0c218fefaf5705c6830deda
        git checkout -f FETCH_HEAD
        ;;
    aarch64*)
        ARCH=arm64
        CONFIG=cat_defconfig
        git fetch --depth=1 origin 90681e12950fbcd0a6bc5bc4f05cc702a6dd6dda
        git checkout -f FETCH_HEAD
        ./scripts/config --file arch/arm64/configs/cat_defconfig \
            -e LD_DEAD_CODE_DATA_ELIMINATION \
            -e CAT_OPTIMIZE \
            -e LTO_GCC
        ;;
    esac

    PATH="${PREFIX_PGO}/${TARGET}/bin:${PATH}" make -j${NPROC} O=out CROSS_COMPILE=${CURRENT_TARGET}- ${CONFIG}
    PATH="${PREFIX_PGO}/${TARGET}/bin:${PATH}" make -j${NPROC} O=out CROSS_COMPILE=${CURRENT_TARGET}-

    if [ -a out/arch/${ARCH}/boot/*Image ]; then
        send_info "<b>GitHub Action : </b><pre>Kernel build finished ! ! !</pre>"
        cd -
    else
        send_info "<b>GitHub Action : </b><pre>Kernel build failed ! ! !</pre>"
        cd -
        exit 1
    fi
}

send_info "
<b>Date : </b><pre>${BUILD_DAY}</pre>
<b>GitHub Action : </b><pre>Toolchain compilation started . . .</pre>

<b>Script </b><pre>${HEAD_SCRIPT}</pre>
<b>GCC </b><pre>${HEAD_GCC}</pre>
<b>Binutils </b><pre>${HEAD_BINUTILS}</pre>"
build_zstd
for TARGET in ${TARGETS[@]}; do
    rm -rf ${PROFILES}/*
    build_binutils ${TARGET}
    build_gcc ${TARGET}
    kernel ${TARGET}
    FINAL=true
    build_binutils ${TARGET}
    build_gcc ${TARGET}
done
strip_binaries
git_push
send_info "<b>GitHub Action : </b><pre>All job finished ! ! !</pre>"
