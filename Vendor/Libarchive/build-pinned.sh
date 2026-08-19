#!/bin/sh
set -eu
expected=c7b847b57feacf5e182f4d14dd6cae545ac6843d55cb725f58e107cdf1c9ad73
actual=$(shasum -a 256 libarchive-3.8.4.tar.xz | awk '{print $1}')
test "$actual" = "$expected"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
tar -xf libarchive-3.8.4.tar.xz -C "$build"
cd "$build/libarchive-3.8.4"
MACOSX_DEPLOYMENT_TARGET=14.0 CPPFLAGS="-I$OLDPWD/BuildHeaders" CFLAGS='-mmacosx-version-min=14.0' LDFLAGS='-mmacosx-version-min=14.0' ./configure \
  --disable-shared --enable-static --without-xml2 --without-expat --without-openssl \
  --without-nettle --without-libb2 --without-lz4 --without-zstd --without-cng \
  --without-mbedtls --without-lzo2
MACOSX_DEPLOYMENT_TARGET=14.0 make -j4 libarchive.la
xcodebuild -create-xcframework -library .libs/libarchive.a -headers libarchive -output "$OLDPWD/Libarchive.xcframework"
