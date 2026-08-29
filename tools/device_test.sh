#!/usr/bin/env bash
# 真机冒烟测试: 把 mt_cli + libmtcore.so + 模型 push 到手机, 跑六个翻译方向。
#
# 这一次运行同时回答四个问题:
#   1. STQ1_0 模型能不能在真机加载 (PR #22836 的 NEON kernel 是否真的работает)
#   2. 三语互译输出是否正常, prompt 拼得对不对
#   3. 哈萨克语输出落在哪套文字 (阿拉伯字母 / 西里尔) → 决定要不要转写层
#   4. 加载耗时、单句耗时、峰值内存
#
# 用法: bash tools/device_test.sh [--threads N] [--ctx N] [--official]
set -uo pipefail

# Git Bash (MSYS) 会把 /data/local/tmp 这种 POSIX 路径改写成 C:/Program Files/Git/data/...
# 传给 adb 就全错了。这两个变量关掉自动路径转换。
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

DEV_DIR=/data/local/tmp/tilmach
MODEL_LOCAL="D:/tilmach/models/Hy-MT1.5-1.8B-1.25bit.gguf"
MODEL_DEV="$DEV_DIR/model.gguf"
OUT="D:/tilmach/out/android-arm64"
EXTRA="$*"

command -v adb >/dev/null || { echo "找不到 adb" >&2; exit 1; }

N_DEV="$(adb devices | grep -cw device || true)"
if [ "$N_DEV" -eq 0 ]; then
  echo "没有检测到设备。请:" >&2
  echo "  1. 手机用数据线连电脑" >&2
  echo "  2. 开发者选项里打开 USB 调试" >&2
  echo "  3. 手机上弹出的授权对话框点「允许」" >&2
  echo "  4. 再跑一次 adb devices 确认状态是 device 而不是 unauthorized" >&2
  exit 1
fi

echo "=== 设备信息 ==="
adb shell getprop ro.product.model
adb shell getprop ro.soc.model 2>/dev/null || adb shell getprop ro.board.platform
adb shell getprop ro.build.version.release
echo -n "abi     : "; adb shell getprop ro.product.cpu.abi
echo -n "内存    : "; adb shell "grep MemTotal /proc/meminfo"
echo -n "大核    : "; adb shell "cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq 2>/dev/null | sort -u | tr '\n' ' '"
echo

echo "=== 推送 ==="
adb shell "mkdir -p $DEV_DIR"
adb push "$OUT/libmtcore.so" "$DEV_DIR/" >/dev/null
adb push "$OUT/mt_cli"       "$DEV_DIR/" >/dev/null
adb shell "chmod 755 $DEV_DIR/mt_cli"

# 模型 440MB, 用 sha256 判断设备上那份是不是最新的。
# 不能只比大小: 归一化 GGUF 类型号是就地改 u32 字段, 文件大小一模一样,
# 只比大小会把旧文件当成新的跳过, 白白排查半天。
SUM_CACHE="D:/tilmach/out/model.sha256"
if [ ! -f "$SUM_CACHE" ] || [ "$MODEL_LOCAL" -nt "$SUM_CACHE" ]; then
  echo -n "计算本地模型 sha256 ... "
  sha256sum "$MODEL_LOCAL" | cut -d' ' -f1 > "$SUM_CACHE"
  echo "done"
fi
WANT_SUM="$(cat "$SUM_CACHE")"
HAVE_SUM="$(adb shell "cat $DEV_DIR/model.sha256 2>/dev/null" | tr -d '\r\n ')"
if [ "$HAVE_SUM" != "$WANT_SUM" ]; then
  echo "推送模型 ($(($(stat -c %s "$MODEL_LOCAL") / 1024 / 1024)) MB)..."
  adb push "$MODEL_LOCAL" "$MODEL_DEV"
  adb shell "echo $WANT_SUM > $DEV_DIR/model.sha256"
else
  echo "模型已是最新 (sha256 ${WANT_SUM:0:12}...), 跳过推送"
fi
echo

run() {   # run <目标语言名> <文本> <说明>
  echo "──────── $3"
  adb shell "cd $DEV_DIR && LD_LIBRARY_PATH=$DEV_DIR ./mt_cli ./model.gguf '$1' '$2' $EXTRA"
  echo
}

echo "=== 六个方向 ==="
# 涉及中文 → 中文指令 + 中文语言全名
run '维吾尔语' '今天天气很好，我们去公园散步吧。' 'zh → ug'
run '哈萨克语' '今天天气很好，我们去公园散步吧。' 'zh → kk  ★ 重点看输出是阿拉伯字母还是西里尔'
run '中文'     'بۈگۈن ھاۋا بەك ياخشى، بىز باغقا سەيلە قىلىپ چىقايلى.' 'ug → zh'
run '中文'     'Бүгін ауа өте жақсы, паркке серуендеуге барайық.'      'kk(西里尔) → zh'
# 不涉及中文 → 英文指令 + 英文语言全名
run 'Kazakh'   'بۈگۈن ھاۋا بەك ياخشى.' 'ug → kk  ★ 同样看文字'
run 'Uyghur'   'Бүгін ауа өте жақсы.'  'kk → ug'

echo "=== 峰值内存 (再跑一句, 同时采样 RSS) ==="
adb shell "cd $DEV_DIR && LD_LIBRARY_PATH=$DEV_DIR ./mt_cli ./model.gguf 维吾尔语 '谢谢你的帮助。' $EXTRA >/dev/null 2>&1 &
  sleep 1
  for i in \$(seq 1 40); do
    p=\$(pidof mt_cli 2>/dev/null)
    [ -z \"\$p\" ] && break
    grep VmRSS /proc/\$p/status 2>/dev/null
    sleep 0.3
  done | sort -k2 -n | tail -1"

echo
echo "=== llama-bench (纯解码速度基准, 可选) ==="
echo "如需要: adb push \"D:/tilmach/engine/third_party/llama.cpp/build-android-arm64/bin-stripped/llama-bench\" $DEV_DIR/"
echo "        adb shell \"cd $DEV_DIR && ./llama-bench -m ./model.gguf -ngl 0 -t 4\""
