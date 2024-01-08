#!/bin/bash
set -ex

source $HOME/.build_env

$SWIFT_SRC/swift/utils/build-script --preset buildbot_linux_crosscompile_android,tools=RA,stdlib=RD,build,armv7 \
    --android-api-level=24 \
    ndk_path=$ANDROID_NDK \
    install_destdir=$DST_ROOT/swift-nightly-install \
    installable_package=$DST_ROOT/swift-android.tar.gz

mv $DST_ROOT/swift-nightly-install/usr/lib/swift $DST_ROOT/swift-nightly-install/usr/lib/swift-armv7
rm -rf $SWIFT_SRC/build/buildbot_linux/swift-linux-x86_64/stdlib