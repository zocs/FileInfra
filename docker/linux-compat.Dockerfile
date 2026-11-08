# linux-compat.Dockerfile
# Ubuntu 18.04 (glibc 2.27) 构建环境，产物兼容 glibc 2.27+。
# 实验已验证：Flutter 3.47 引擎只需 GLIBC_2.18，此环境下链接的
# 主程序只需 GLIBC_2.2.5，完全兼容 Ubuntu 18.04 及更老发行版。
# 唯一需要外部升级的是 cmake（18.04 自带 3.10，Flutter 3.47 需 ≥ 3.14）。

FROM ubuntu:18.04
ARG FLUTTER_VERSION=3.47.0
ARG RUST_VERSION=1.99.1

# 基础工具
# 双编译器策略：
#  - dufs 的 C 依赖（aws-lc-sys 等）使用 -Wno-deprecated-literal-operator（GCC flag），
#    clang 6/10 都不支持 → 必须用 gcc（ENV CC/CXX 强制）。
#  - Flutter Linux 构建强制 CXX=clang++（CMake 里硬编码）→ 必须装 clang++，
#    否则 CMake 报「Could not find compiler set in environment variable CXX: clang++」。
RUN apt-get update && \
    apt-get install -y \
      curl git xz-utils unzip python3 \
      ninja-build pkg-config \
      clang-10 \
      libgtk-3-dev libsecret-1-dev \
      libayatana-appindicator3-dev \
      build-essential ca-certificates \
      libfuse2 && \
    # 让 clang++ 命令可用（Flutter 用），但不要覆盖 cc/c++ 的默认（gcc 留给 dufs）
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-10 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-10 100 && \
    rm -rf /var/lib/apt/lists/*
# 确保 dufs 的 Rust cc crate 用 gcc（不是 clang）
# 注意：Flutter 构建时会自己覆盖 CXX=clang++，不影响它
ENV CC=gcc
ENV CXX=g++

# cmake 3.28（官方预编译二进制，静态）
RUN curl -sL -o /tmp/cmake.tar.gz \
      'https://github.com/Kitware/CMake/releases/download/v3.28.6/cmake-3.28.6-linux-x86_64.tar.gz' && \
    tar xzf /tmp/cmake.tar.gz -C /opt/ && \
    rm /tmp/cmake.tar.gz
ENV PATH="/opt/cmake-3.28.6-linux-x86_64/bin:${PATH}"

# Passed from the same pinned toolchain versions as the native CI jobs.
RUN curl -sL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" && \
    tar xf /tmp/flutter.tar.xz -C /opt/ && \
    rm /tmp/flutter.tar.xz && \
    git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"

# Rust version is fixed, including patch level.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal --no-modify-path
ENV PATH="/root/.cargo/bin:${PATH}"

# 预 cache flutter linux 引擎（避免构建时下载）
RUN flutter precache --linux --no-version-check 2>/dev/null; true

WORKDIR /src
