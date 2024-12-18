#!/bin/bash
set -ex

# ============================
# Initial Setup and Environment Variables
# ============================

# Source environment variables from the build environment file
source "$HOME/.build_env"

# Set the ICU version
export ICU_VERSION=73

# Determine the directory where the script is located
self_dir=$(realpath "$(dirname "$0")")

# Read command-line arguments
arch=$1          # e.g., arm64, arm, x86, x86_64
swift_arch=$2    # e.g., aarch64, armv7, i686, x86_64
clang_arch=$3    # e.g., aarch64-linux-android, arm-linux-androideabi, i686-linux-android, x86_64-linux-android
abi=$4           # e.g., arm64-v8a, armeabi-v7a, x86, x86_64
ndk_arch=$5      # e.g., aarch64-linux-android, armv7a-linux-androideabi, i686-linux-android, x86_64-linux-android

# Define build directories
dispatch_build_dir="/tmp/swift-corelibs-libdispatch-$arch"
foundation_build_dir="/tmp/foundation-$arch"
xctest_build_dir="/tmp/xctest-$arch"

# Define paths to dependencies
icu_libs="$ICU_LIBS/build-$ndk_arch"
openssl_libs="$OPENSSL_LIBS/$arch"
curl_libs="$CURL_LIBS/$arch"
libxml_libs="$LIBXML_LIBS/$arch"

# ============================
# Install a Fresh Version of CMake
# ============================

# Remove any existing CMake installation
apt remove --purge --auto-remove -y cmake

# Specify the desired CMake version
version=3.27
build=7

# Download the specified version of CMake
wget "https://cmake.org/files/v$version/cmake-$version.$build-linux-x86_64.sh"

# Install CMake to /opt/cmake
mkdir /opt/cmake
sh "cmake-$version.$build-linux-x86_64.sh" --prefix=/opt/cmake --skip-license

# Create a symbolic link to make the new CMake version accessible system-wide
ln -sf /opt/cmake/bin/cmake /usr/local/bin/cmake

# Verify the CMake installation
cmake --version

# ============================
# Clean Previous Builds
# ============================

# Remove any existing build directories to ensure a clean build
rm -rf "$dispatch_build_dir" "$foundation_build_dir" "$xctest_build_dir"

# Create fresh build directories
mkdir -p "$dispatch_build_dir" "$foundation_build_dir" "$xctest_build_dir"

# ============================
# Configure and Build libdispatch
# ============================

pushd "$dispatch_build_dir"
    cmake "$DISPATCH_SRC" \
        -G Ninja \
        -C "$self_dir/common-flags.cmake" \
        -C "$self_dir/common-flags-$arch.cmake" \
        -DENABLE_SWIFT=YES

    cmake --build "$dispatch_build_dir" --verbose
popd

# ============================
# Configure Foundation (CMake Configuration)
# ============================

pushd "$foundation_build_dir"
    cmake "$FOUNDATION_SRC" \
        -G Ninja \
        -C "$self_dir/common-flags.cmake" \
        -C "$self_dir/common-flags-$arch.cmake" \
        -Ddispatch_DIR="$dispatch_build_dir/cmake/modules" \
        -DCURL_LIBRARY="$curl_libs/lib/libcurl.so" \
        -DCURL_INCLUDE_DIR="$curl_libs/include" \
        -DLIBXML2_LIBRARY="$libxml_libs/lib/libxml2.so" \
        -DLIBXML2_INCLUDE_DIR="$libxml_libs/include/libxml2" \
        -DCMAKE_HAVE_LIBC_PTHREAD=YES
popd

# ============================
# Apply Patches to Foundation Source
# ============================

# Define the Foundation source directory
FOUNDATION_SRC_DIR="$foundation_build_dir/_deps/swiftfoundation-src/Sources/FoundationEssentials"

# Verify that the Foundation source directory exists
if [ ! -d "$FOUNDATION_SRC_DIR" ]; then
    echo "Error: Foundation source directory not found at $FOUNDATION_SRC_DIR"
    exit 1
fi

# --- 1. Fix the 'nil' Pointer Issue in FileOperations+Enumeration.swift ---

FILE_ENUMERATION="$FOUNDATION_SRC_DIR/FileManager/FileOperations+Enumeration.swift"

if [ -f "$FILE_ENUMERATION" ]; then
    echo "Patching FileOperations+Enumeration.swift to handle 'nil' pointers..."

    # Backup the original file
    cp "$FILE_ENUMERATION" "${FILE_ENUMERATION}.bak"

    # Replace the problematic line using 'sed'
    # Original line:
    # state = [UnsafeMutablePointer(mutating: path), nil].withUnsafeBufferPointer { dirList in
    # Replacement:
    # let paths: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: path), nil]
    # state = paths.withUnsafeBufferPointer { dirList in

    sed -i '/state = \[UnsafeMutablePointer(mutating: path), nil\].withUnsafeBufferPointer {/c\
let paths: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: path), nil]\n\
state = paths.withUnsafeBufferPointer { dirList in' "$FILE_ENUMERATION"

else
    echo "Error: FileOperations+Enumeration.swift not found at $FILE_ENUMERATION"
    exit 1
fi

# --- 2. Replace 'futimes' with 'futimens' in FileOperations.swift ---

FILE_OPERATIONS="$FOUNDATION_SRC_DIR/FileManager/FileOperations.swift"

if [ -f "$FILE_OPERATIONS" ]; then
    echo "Patching FileOperations.swift to replace 'futimes' with 'futimens'..."

    # Backup the original file
    cp "$FILE_OPERATIONS" "${FILE_OPERATIONS}.bak"

    # Replace the 'if futimes...' line with conditional compilation using 'sed'
    # Original line:
    # if futimes(dstFD, $0) != 0 {
    # Replacement:
    # #if canImport(Darwin)
    #     if futimes(dstFD, $0) != 0 {
    # #else
    #     if futimens(dstFD, $0) != 0 {
    # #endif

    sed -i '/if futimes(dstFD, \$0) != 0 {/c\
#if canImport(Darwin)\n\
    if futimes(dstFD, $0) != 0 {\n\
#else\n\
    if futimens(dstFD, $0) != 0 {\n\
#endif' "$FILE_OPERATIONS"

else
    echo "Error: FileOperations.swift not found at $FILE_OPERATIONS"
    exit 1
fi

# --- 3. Add 'import Glibc' to FileOperations.swift if not already present ---

if [ -f "$FILE_OPERATIONS" ]; then
    if ! grep -q "^import Glibc" "$FILE_OPERATIONS"; then
        echo "Adding 'import Glibc' to FileOperations.swift..."

        # Insert 'import Glibc' at the very top of the file
        sed -i '1i\
import Glibc
' "$FILE_OPERATIONS"
    fi
else
    echo "Error: FileOperations.swift not found at $FILE_OPERATIONS"
    exit 1
fi

# ============================
# Configure and Build Foundation
# ============================

# Proceed to build Foundation after applying patches
pushd "$foundation_build_dir"
    cmake --build "$foundation_build_dir" --verbose
popd

# ============================
# Configure and Build XCTest
# ============================

pushd "$xctest_build_dir"
    cmake "$XCTEST_SRC" \
        -G Ninja \
        -C "$self_dir/common-flags.cmake" \
        -C "$self_dir/common-flags-$arch.cmake" \
        -DENABLE_TESTING=NO \
        -Ddispatch_DIR="$dispatch_build_dir/cmake/modules" \
        -DFoundation_DIR="$foundation_build_dir/cmake/modules"

    cmake --build "$xctest_build_dir" --verbose
popd

# ============================
# Install the Built Components
# ============================

# Install libdispatch
cmake --build "$dispatch_build_dir" --target install

# Install Foundation
cmake --build "$foundation_build_dir" --target install

# Install XCTest
cmake --build "$xctest_build_dir" --target install

# ============================
# Copy Dependency Headers and Libraries
# ============================

swift_include="$HOME/swift-toolchain/usr/lib/swift-$swift_arch"
dst_libs="$HOME/swift-toolchain/usr/lib/swift-$swift_arch/android"

# Ensure the destination libraries directory exists
mkdir -p "$dst_libs"

# Synchronize the required libraries
rsync -av "$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$clang_arch/libc++_shared.so" "$dst_libs"

rsync -av "$icu_libs"/*"$ICU_VERSION".so "$dst_libs"
rsync -av "$openssl_libs/lib/libcrypto.a" "$dst_libs"
rsync -av "$openssl_libs/lib/libssl.a" "$dst_libs"
rsync -av "$curl_libs/lib/libcurl.*" "$dst_libs"
rsync -av "$libxml_libs/lib/libxml2.*" "$dst_libs"

# Copy the required headers
cp -r "$icu_libs/include/unicode" "$swift_include"
cp -r "$openssl_libs/include/openssl" "$swift_include"
cp -r "$curl_libs/include/curl" "$swift_include"
cp -r "$libxml_libs/include/libxml2/libxml" "$swift_include"

echo "Build and installation completed successfully."
