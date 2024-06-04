#!/bin/bash
set -ex

# Copied from https://github.com/apple/swift-docker/blob/main/swift-ci/master/ubuntu/20.04/Dockerfile
apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get -y install \
  build-essential       \
  cmake                 \
  git                   \
  icu-devtools          \
  libcurl4-openssl-dev  \
  libedit-dev           \
  libicu-dev            \
  libncurses5-dev       \
  libpython3-dev        \
  libsqlite3-dev        \
  libxml2-dev           \
  ninja-build           \
  pkg-config            \
  python                \
  python-six            \
  python2-dev           \
  python3-six           \
  python3-distutils     \
  python3-pkg-resources \
  python3-psutil        \
  rsync                 \
  swig                  \
  systemtap-sdt-dev     \
  tzdata                \
  uuid-dev              \
  zip

apt-get install -y  \
    lsb-release                 \
    software-properties-common  \
    gnupg                       \
    autoconf                    \
    automake                    \
    libtool                     \
    curl                        \
    wget                        \
    unzip                       \
    vim                         \
    rpl

# Install clang 13
wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-13 main"
apt-get update
apt-get install -y clang-13
update-alternatives --install /usr/bin/clang clang /usr/bin/clang-13 100
update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-13 100
update-alternatives --set clang /usr/bin/clang-13
update-alternatives --set clang++ /usr/bin/clang++-13
clang --version
