#!/usr/bin/env bash
# 断点续传下载 1.25bit STQ1_0 模型。
# hf-mirror 会 302 到 AWS CDN, 那一段经常中途断流 (schannel: server closed abruptly),
# 所以这里用「循环 + curl -C -」硬续到字节数对齐为止, 而不是指望 curl --retry。
set -uo pipefail

DEST="${1:-D:/tilmach/models/Hy-MT1.5-1.8B-1.25bit.gguf}"
URL="https://hf-mirror.com/tencent/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf"
WANT=461860704          # X-Linked-Size, 440 MiB
MAX_TRIES=200

size_of() { stat -c %s "$1" 2>/dev/null || echo 0; }

for i in $(seq 1 "$MAX_TRIES"); do
  have="$(size_of "$DEST")"
  if [ "$have" -ge "$WANT" ]; then break; fi
  echo "[$i] 已有 $have / $WANT 字节 ($((have * 100 / WANT))%), 续传中..."
  curl -L -C - --max-time 900 --connect-timeout 20 \
       --speed-limit 20000 --speed-time 60 \
       -sS -o "$DEST" "$URL" || true
  sleep 2
done

have="$(size_of "$DEST")"
if [ "$have" -ne "$WANT" ]; then
  echo "下载未完成: $have / $WANT" >&2
  exit 1
fi
echo "下载完成: $have 字节"
echo -n "sha256: "; sha256sum "$DEST" | cut -d' ' -f1
