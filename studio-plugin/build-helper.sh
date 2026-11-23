#!/bin/bash
set -eu
cd "$(dirname "$0")"
out=com.ulanzi.openless.ulanziPlugin/bin/helper
swiftc -O -target arm64-apple-macos13.0 native/helper.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker native/Info.plist -o "$out"
codesign --force --sign - --identifier com.ulanzi.openless.helper "$out"
