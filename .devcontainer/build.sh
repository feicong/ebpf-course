# Copyright (c) 2024-2025 fei_cong(https://github.com/feicong/ebpf-course)
#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error: in $0 on line $LINENO"' ERR

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run script as root user."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export TZ="Asia/Shanghai"

ARCH="$(uname -m)"

# Update apt sources list based on architecture
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "i686" ] || [ "$ARCH" = "x86" ]; then
    tee /etc/apt/sources.list <<EOF
# Default mirror with commented source repositories for faster updates
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF
else
    tee /etc/apt/sources.list <<EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# 镜像仅包含 32/64 位 x86 架构处理器的软件包，在 ARM(arm64, armhf)、PowerPC(ppc64el)、RISC-V(riscv64) 和 S390x 等架构的设备上（对应官方源为 ports.ubuntu.com）请使用 ubuntu-ports 镜像
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse

# 以下安全更新软件源包含了官方源与镜像站配置，如有需要可自行修改注释切换
deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
# # deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
EOF
fi

# Install required packages
apt-get update && \
    apt-get install -y --no-install-recommends \
        libzstd-dev libcurl4-openssl-dev libedit-dev cmake vim \
        lsb-release software-properties-common tree sed wget apt-file \
        gnupg unzip ninja-build git python3-dev python3-pip \
        libdwarf-dev libelf-dev libsqlite3-dev libunwind-dev \
        curl xz-utils build-essential file flex bison meson \
        gh tzdata plantuml qemu-user ca-certificates \
        gperf pkg-config python-is-python3 reprepro sudo adb socat \
        help2man autoconf gawk libtool-bin libncurses-dev texinfo unifdef p7zip-full && \
    apt-file update && \
    apt-get install -y --no-install-recommends \
        lib32stdc++-9-dev libc6-dev libc6-dev-i386 gcc-multilib g++-multilib || true

# Set timezone
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Configure Python pip
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    python3 -m pip install -U pip && \
    pip install -U lief ninja meson typing-extensions colorama prompt-toolkit pygments graphlib

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm config set strict-ssl false && \
    npm config set registry https://registry.npm.taobao.org

# Install Go
export GO_VERSION=1.23.2
export GOROOT=/usr/local/go
export GOPATH=/go
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
export GO111MODULE=on
export GOPROXY=https://goproxy.cn,direct

ARCH="$(uname -m)" && \
    case $ARCH in \
        "x86_64") ARCH=amd64 ;; \
        "aarch64") ARCH=arm64 ;; \
        "armv6" | "armv7l") ARCH=armv6l ;; \
        "armv8") ARCH=arm64 ;; \
        "i686") ARCH=386 ;; \
        "*386*") ARCH=386 ;; \
        *) echo "Unsupported architecture"; exit 1 ;; \
    esac && \
    PACKAGE_NAME="go${GO_VERSION}.linux-$ARCH.tar.gz" && \
    TEMP_DIRECTORY=$(mktemp -d) && \
    echo "Downloading $PACKAGE_NAME ..." && \
    wget -q https://mirrors.aliyun.com/golang/$PACKAGE_NAME -O "$TEMP_DIRECTORY/go.tar.gz" && \
    echo "Extracting File..." && \
    mkdir -p "$GOROOT" && \
    tar -C "$GOROOT" --strip-components=1 -xzf "$TEMP_DIRECTORY/go.tar.gz" && \
    rm -rf "$TEMP_DIRECTORY" && \
    mkdir -p "${GOPATH}/"{src,pkg,bin}

go version

# Install additional required packages
apt-get update -y && apt-get install -y --no-install-recommends \
    apt-utils python3-full python3-pip acl sysbench jq net-tools \
    wget curl git tree pkg-config vim clang llvm libbfd-dev libcap-dev \
    dialog file libelf-dev gpg flex bison libssl-dev zip \
    unzip build-essential bc libstdc++6 libpulse0 libglu1-mesa \
    zlib1g-dev libelf-dev libfl-dev python3-setuptools \
    liblzma-dev libdebuginfod-dev arping netperf iperf systemtap-sdt-dev \
    binutils-dev libcereal-dev llvm-dev libclang-dev libpcap-dev \
    libgtest-dev libgmock-dev pahole lld libelf1 rsync kmod cpio xz-utils \
    git-lfs s-tui stress htop locales lcov libncurses6 libncurses-dev devscripts

# Clone and build eBPF tools
mkdir -p eBPF
pushd eBPF

git_clone_or_pull() {
    local repo_url=$1
    local dir_name=$2
    if [ ! -d "$dir_name" ]; then
        git clone --progress --recursive "$repo_url" "$dir_name"
    else
        git -C "$dir_name" pull
    fi
}

git_clone_or_pull https://github.com/iovisor/bcc.git bcc
git_clone_or_pull https://github.com/bpftrace/bpftrace.git bpftrace
git_clone_or_pull https://github.com/libbpf/libbpf.git libbpf
git_clone_or_pull https://github.com/libbpf/libbpf-bootstrap.git libbpf-bootstrap
git_clone_or_pull https://github.com/libbpf/bpftool.git bpftool

# Static link binaries
EXTRA_CFLAGS=--static

pushd libbpf/src
make -j$(nproc)
sudo make install
popd

pushd libbpf-bootstrap/examples/c
make -j$(nproc)
popd

pushd bpftool/src
make -j$(nproc)
sudo make install
popd

mkdir -p bcc/build
pushd bcc/build
LLVM_ROOT=/usr/lib/llvm-14 cmake ..
make -j$(nproc)
sudo make install
cmake -DPYTHON_CMD=python3 ..
pushd src/python/
make -j$(nproc)
sudo make install
popd
popd

pushd bcc/libbpf-tools/
make -j$(nproc) BPFCFLAGS="-g -O2 -Wall -I/usr/include/$(uname -m)-linux-gnu"
sudo make install
popd

mkdir -p bpftrace/build
pushd bpftrace/build
LLVM_ROOT=/usr/lib/llvm-14 cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF ..
make -j$(nproc)
sudo make install
popd

popd

cp -f /eBPF/libbpf/src/libbpf.so.1 /lib/$(uname -m)-linux-gnu/libbpf.so.1 || true
rm -rf /eBPF
