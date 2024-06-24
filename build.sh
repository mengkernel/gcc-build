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
TARGETS=(aarch64-linux-gnu)
HEAD_SCRIPT="$(git log -1 --oneline)"
HEAD_GCC="$(git --git-dir gcc/.git log -1 --oneline)"
HEAD_BINUTILS="$(git --git-dir binutils/.git log -1 --oneline)"
GCC="${PREFIX}/${TARGETS[0]}/bin/${TARGETS[0]}-gcc"
BINUTILS="${PREFIX}/${TARGETS[0]}/bin/${TARGETS[0]}-ld"
PKG_VERSION="CAT"
BINUTILS_VERSION=$(grep "^PACKAGE_VERSION=" "${WORK_DIR}/binutils/ld/configure" | grep -oP "'\K[^']+(?=')")
FULL_VERSION=$(cat "${WORK_DIR}/gcc/gcc/BASE-VER")
MAJOR_VERSION=$(echo ${FULL_VERSION} | cut -d '.' -f 1)
KERNEL="${WORK_DIR}/kernel"
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
    PREFIX_PGO GEN_FLAGS USE_FLAGS GCC BINUTILS FULL_VERSION \
    MAJOR_VERSION

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
    mkdir -p ${WORK_DIR}/build-zstd
    cd ${WORK_DIR}/build-zstd
    cmake ${WORK_DIR}/zstd/build/cmake \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}/zstd" \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache |& tee -a build.log
    make -j${NPROC} |& tee -a build.log
    make install -j${NPROC} |& tee -a build.log

    # check Zstd build status
    if [ -f "${PREFIX}/zstd/bin/zstd" ]; then
        #    send_info "<b>GitHub Action : </b><pre>Zstd build finished ! ! !</pre>"
        true
    else
        send_info "<b>GitHub Action : </b><pre>Zstd build failed ! ! !</pre>"
        send_file ${WORK_DIR}/build-zstd/build.log "Zstd build.log"
        exit 1
    fi
}

build_binutils() {
    CURENT_TARGET=${1}
    #  send_info "<b>GitHub Action : </b><pre>Binutils build started . . .</pre><b>Target : </b><pre>[${CURENT_TARGET}]</pre>"

    rm -rf ${WORK_DIR}/build-binutils
    mkdir -p ${WORK_DIR}/build-binutils
    cd ${WORK_DIR}/build-binutils

    # Check compiler
    gcc -v |& tee -a build.log
    ld -v |& tee -a build.log

    if ${FINAL}; then
        ADD="${USE_FLAGS}"
        PREFIX_ADD="${PREFIX}"
    else
        ADD="${GEN_FLAGS}"
        PREFIX_ADD="${PREFIX_PGO}"
    fi

    env CC="ccache gcc" CXX="ccache g++" \
        CFLAGS="${OPT_FLAGS} ${ADD}" \
        CXXFLAGS="${OPT_FLAGS} ${ADD}" \
        ../binutils/configure \
        --disable-checking \
        --disable-compressed-debug-sections \
        --disable-dependency-tracking \
        --disable-gdb \
        --disable-gold \
        --disable-gprofng \
        --disable-multilib \
        --disable-nls \
        --disable-shared \
        --enable-64-bit-archive \
        --enable-64-bit-bfd \
        --enable-ld \
        --enable-plugins \
        --enable-threads=posix \
        --prefix=${PREFIX_ADD}/${CURENT_TARGET} \
        --program-prefix=${CURENT_TARGET}- \
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
        true
    else
        send_info "<b>GitHub Action : </b><pre>Binutils build failed ! ! !</pre>"
        send_file ${WORK_DIR}/build-binutils/build.log "Binutils build.log"
        exit 1
    fi
}

build_gcc() {
    CURENT_TARGET=${1}
    #  send_info "<b>GitHub Action : </b><pre>GCC build started . . .</pre><b>Target : </b><pre>[${CURENT_TARGET}]</pre>"

    rm -rf ${WORK_DIR}/build-gcc
    mkdir -p ${WORK_DIR}/build-gcc
    cd ${WORK_DIR}/build-gcc

    # Check compiler
    gcc -v |& tee -a build.log
    ld -v |& tee -a build.log

    case ${CURENT_TARGET} in
    x86_64*)
        EXTRA_CONF="--without-cuda-driver"
        ;;
    aarch64*)
        EXTRA_CONF="--enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419 --with-headers=/usr/include"
        ;;
    esac

    if ${FINAL}; then
        ADD="${USE_FLAGS}"
        PREFIX_ADD="${PREFIX}"
    else
        ADD="${GEN_FLAGS}"
        PREFIX_ADD="${PREFIX_PGO}"
    fi

    env CC="ccache gcc" CXX="ccache g++" \
        CFLAGS="${OPT_FLAGS} ${ADD}" \
        CXXFLAGS="${OPT_FLAGS} ${ADD}" \
        ../gcc/configure \
        --disable-bootstrap \
        --disable-checking \
        --disable-cet \
        --disable-gcov \
        --disable-libada \
        --disable-libgm2 \
        --disable-libquadmath \
        --disable-libquadmath-support \
        --disable-libstdcxx-debug \
        --disable-libstdcxx-pch \
        --disable-multilib \
        --disable-nls \
        --disable-shared \
        --enable-default-pie \
        --enable-default-ssp \
        --enable-gnu-indirect-function \
        --enable-languages=c,c++ \
        --enable-linux-futex \
        --enable-libssp \
        --enable-threads=posix \
        --prefix=${PREFIX_ADD}/${CURENT_TARGET} \
        --program-prefix=${CURENT_TARGET}- \
        --target=${CURENT_TARGET} \
        --with-gnu-as \
        --with-gnu-ld \
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
        true
    else
        send_info "<b>GitHub Action : </b><pre>GCC build failed ! ! !</pre>"
        send_file ${WORK_DIR}/build-gcc/build.log "GCC build.log"
        exit 1
    fi
}

strip_binaries() {
    cd ${PREFIX}
    find . -type f -exec file {} \; >.file-idx

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

    rm -rf stripp-* .file-idx
    find . -name '*.a' -delete -or -name '*.la' -delete
}

git_push() {
    send_info "<b>GitHub Action : </b><pre>Release into GitHub . . .</pre>"

    if ${MASTER}; then
        git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/mengkernel/gcc ${WORK_DIR}/gcc-repo -b main
    else
        git clone https://Diaz1401:${GITHUB_TOKEN}@github.com/Diaz1401/gcc-stable ${WORK_DIR}/gcc-repo -b main
    fi

    cd ${WORK_DIR}/gcc-repo
    GCC_CONFIG="$(${GCC} -v 2>&1)"
    MESSAGE="GCC: ${MAJOR_VERSION}-${BUILD_DATE}, Binutils: ${BINUTILS_VERSION}"
    git config --global user.name github-actions[bot]
    git config --global user.email github-actions[bot]@users.noreply.github.com

    # Generate archive
    cp -rf ${PREFIX}/*-linux-gnu .
    tar -I"${PREFIX}/zstd/bin/zstd --ultra -22 -T0" -cf gcc.tar.zst *
    cat README |
        sed s:GCCVERSION:${MAJOR_VERSION}-${BUILD_DATE}:g |
        sed s:BINUTILSVERSION:${BINUTILS_VERSION}:g >README.md
    git commit --allow-empty -as \
        -m "${MESSAGE}" \
        -m "${GCC_CONFIG}"
    git push origin main
    hub release create -a gcc.tar.zst -m "${MESSAGE}" ${BUILD_TAG}
}

compile_kernel() {
    CURRENT_TARGET=${1}
    send_info "<b>GitHub Action : </b><pre>Kernel build started . . .</pre>"

    # Symlink liblto_plugin.so
    cd ${PREFIX_PGO}/${CURRENT_TARGET}/lib/bfd-plugins
    ln -sr ../../libexec/gcc/${CURRENT_TARGET}/${FULL_VERSION}/liblto_plugin.so .
    cd ${KERNEL}

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
        git fetch --depth=1 origin c5d09825d20d3cd8e7c9a8b07a94adc9a6195e23
        git checkout -f FETCH_HEAD
        wget -qO calcsum.cpp https://raw.githubusercontent.com/openeuler-mirror/A-FOT/master/GcovSummaryAddTool.cpp
        g++ -o calcsum calcsum.cpp
        mkdir -p out
        tar xf profiles.tar.gz -C out
        find out -name "*.gcda" >list.txt
        ./calcsum list.txt
        ./scripts/config --file arch/arm64/configs/cat_defconfig \
            -e LD_DEAD_CODE_DATA_ELIMINATION \
            -e PGO_GEN -e PGO_USE \
            -e CAT_OPTIMIZE \
            -e LTO_GCC
        ;;
    esac

    PATH="${PREFIX_PGO}/${CURRENT_TARGET}/bin:${PATH}" \
        make -j${NPROC} O=out CROSS_COMPILE=${CURRENT_TARGET}- ${CONFIG}
    PATH="${PREFIX_PGO}/${CURRENT_TARGET}/bin:${PATH}" \
        make -j${NPROC} O=out CROSS_COMPILE=${CURRENT_TARGET}-

    if [ -a ${KERNEL}/out/arch/${ARCH}/boot/*Image* ]; then
        send_info "<b>GitHub Action : </b><pre>Kernel build finished ! ! !</pre>"
        rm -rf ${KERNEL}/out
    else
        send_info "<b>GitHub Action : </b><pre>Kernel build failed ! ! !</pre>"
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
    compile_kernel ${TARGET}
    FINAL=true
    build_binutils ${TARGET}
    build_gcc ${TARGET}

    # symlink liblto_plugin.so
    cd ${PREFIX}/${TARGET}/lib/bfd-plugins
    ln -sr ../../libexec/gcc/${TARGET}/${FULL_VERSION}/liblto_plugin.so .
done
strip_binaries
git_push
send_info "<b>GitHub Action : </b><pre>All job finished ! ! !</pre>"
