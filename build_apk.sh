#!/bin/bash
# 智懂你 APK 构建脚本
# 自动添加 --no-tree-shake-icons，避免字体优化步骤卡住
# 用法：./build_apk.sh
cd "$(dirname "$0")"
echo "=== 构建智懂你 APK（release）==="
flutter build apk --release --no-tree-shake-icons
echo "=== 构建完成 ==="
ls -lh build/app/outputs/flutter-apk/app-release.apk
