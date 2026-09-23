#!/usr/bin/env bash
# 白虎阅读 Linux 启动包装
# 处理 Wayland 兼容、sandbox、库路径

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

# 基础参数：
# --no-sandbox: KDE Wayland 下 Electron 9 sandbox 与 setuid 不兼容
# --disable-gpu: Manjaro KDE Wayland 上 GPU 进程偶发黑屏
exec "$DIR/electron" \
  --no-sandbox \
  --disable-gpu \
  "$@"