#!/bin/bash
# 职管家 APK 构建脚本
#
# 用法：
#   ./build_apk.sh              # 默认只打 arm64-v8a（构建快、体积小，覆盖 2017 年后的绝大多数机型）
#   ./build_apk.sh --universal  # 打全 ABI（arm64 + armeabi-v7a + x86_64），兼容 32 位老机型，构建慢约 2/3
#
# 说明：
# - --no-tree-shake-icons：规避本机字体/图标 tree-shaking 偶发的 Gradle 卡死
# - release 默认单 ABI：Dart AOT 只编译一份 libapp.so，实测构建时间与 APK 体积同时下降
set -e
cd "$(dirname "$0")"

TARGET_PLATFORM="android-arm64"
if [ "$1" = "--universal" ]; then
  TARGET_PLATFORM="android-arm,android-arm64,android-x64"
  echo "=== 构建职管家 APK（release · 全 ABI 通用包）==="
else
  echo "=== 构建职管家 APK（release · arm64-v8a）==="
fi

START=$(date +%s)
flutter build apk --release --no-tree-shake-icons --target-platform "$TARGET_PLATFORM"
END=$(date +%s)

echo "=== 构建完成（耗时 $(( (END-START)/60 ))分$(( (END-START)%60 ))秒）==="
ls -lh build/app/outputs/flutter-apk/app-release.apk
