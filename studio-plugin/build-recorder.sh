#!/bin/bash
set -eu
cd "$(dirname "$0")"
bundle="com.ulanzi.openless.ulanziPlugin/bin/OpenLess Recorder.app"
mkdir -p "$bundle/Contents/MacOS"
cp native/recorder.plist "$bundle/Contents/Info.plist"
swiftc -O -target arm64-apple-macos13.0 native/recorder.swift -o "$bundle/Contents/MacOS/OpenLess Recorder"
codesign --force --options runtime --entitlements native/recorder-entitlements.plist --sign - "$bundle"
