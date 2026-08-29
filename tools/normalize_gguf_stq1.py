#!/usr/bin/env python3
"""把官方发布的 Hy-MT1.5 1.25bit GGUF 归一化到当前 llama.cpp PR 分支的类型编号。

## 为什么需要这一步

官方在 HuggingFace 上发布的 `Hy-MT1.5-1.8B-1.25bit.gguf` 是用**早期版本**的
llama.cpp PR #22836 量化的, 那时 STQ1_0 的 ggml 类型号是 42, file_type 是 41。

此后上游主线自己占用了 41 (Q1_0) 和 42 (Q2_0), PR 被 rebase, STQ1_0 顺移:
    GGML_TYPE_Q1_0    = 41
    GGML_TYPE_Q2_0    = 42
    GGML_TYPE_STQ1_0  = 43          ← 现在的 PR HEAD
    LLAMA_FTYPE_MOSTLY_STQ1_0 = 42  ← 现在的 file_type

于是用当前 PR HEAD 加载官方 GGUF 时, 那 224 个权重张量会被当成 Q2_0 解析,
block 尺寸对不上 → 张量大小校验失败 → "加载模型失败"。

## 为什么改文件而不是改引擎

已经核对过: 官方 GGUF 的实际布局是 **42 字节 / 256 元素**, 与当前 PR HEAD 的
`block_stq1_0` (fp16 2 + QK_K/8 32 + QK_K/32 8 = 42) **逐字节一致**。
差别只有枚举编号。所以:

  - 改引擎 → 要在 fork 里和上游的 Q2_0 抢 42 号, 长期维护成本高
  - 改文件 → 只动张量信息表里的 u32 类型字段和一个 KV, 数据段一个字节都不碰,
             引擎保持原样跟 PR 走, 将来 PR 合并进主线可以直接切过去

App 的下载流程里会内置同样的归一化逻辑 (~30 行), 这样用户下的仍然是官方原始文件。

用法:
    python tools/normalize_gguf_stq1.py <model.gguf> [--dry-run] [--backup]
"""
import shutil
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gguf_meta import Reader, U32, U64  # noqa: E402

OLD_TYPE, NEW_TYPE = 42, 43       # GGML_TYPE: 旧 STQ1_0 → 新 STQ1_0
OLD_FTYPE, NEW_FTYPE = 41, 42     # LLAMA_FTYPE_MOSTLY_STQ1_0


def scan(path):
    """走一遍 GGUF, 记录需要改写的位置。

    返回 (type_field_positions, ftype_field_pos, arch, name)
    """
    with open(path, 'rb') as f:
        r = Reader(f)
        if r.raw(4) != b'GGUF':
            raise ValueError('不是 GGUF 文件')
        r.scalar(U32)
        n_tensors = r.scalar(U64)
        n_kv = r.scalar(U64)

        arch = name = None
        ftype_pos = None
        for _ in range(n_kv):
            key = r.string()
            vtype = r.scalar(U32)
            if key == 'general.file_type':
                ftype_pos = f.tell()          # 值紧跟在类型字段之后
            val = r.value(vtype)
            if key == 'general.architecture':
                arch = val
            elif key == 'general.name':
                name = val

        positions = []
        for _ in range(n_tensors):
            r.string()                        # name
            nd = r.scalar(U32)
            for _ in range(nd):
                r.scalar(U64)                 # dims
            pos = f.tell()
            ttype = r.scalar(U32)
            r.scalar(U64)                     # offset
            if ttype == OLD_TYPE:
                positions.append(pos)
        return positions, ftype_pos, arch, name


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = Path(sys.argv[1])
    dry = '--dry-run' in sys.argv
    backup = '--backup' in sys.argv

    positions, ftype_pos, arch, name = scan(path)

    print(f'文件      : {path}')
    print(f'architecture: {arch}')
    print(f'name        : {name}')
    print(f'待改写张量  : {len(positions)} 个 (type {OLD_TYPE} → {NEW_TYPE})')

    # 只对这个模型动手, 免得误伤别的 GGUF
    if arch != 'hunyuan-dense':
        print(f'!! architecture 不是 hunyuan-dense, 拒绝改写', file=sys.stderr)
        return 1
    if not positions:
        print('没有 type=42 的张量 —— 可能已经归一化过, 或官方重新上传了新编号版本。无需操作。')
        return 0

    if dry:
        print('--dry-run: 不写入')
        return 0

    if backup:
        bak = path.with_suffix(path.suffix + '.orig')
        if not bak.exists():
            print(f'备份到 {bak} ...')
            shutil.copy2(path, bak)

    with open(path, 'r+b') as f:
        for pos in positions:
            f.seek(pos)
            f.write(struct.pack('<I', NEW_TYPE))
        if ftype_pos is not None:
            f.seek(ftype_pos)
            cur = struct.unpack('<I', f.read(4))[0]
            if cur == OLD_FTYPE:
                f.seek(ftype_pos)
                f.write(struct.pack('<I', NEW_FTYPE))
                print(f'general.file_type: {OLD_FTYPE} → {NEW_FTYPE}')

    print(f'完成: 改写了 {len(positions)} 个张量类型字段, 数据段未改动')
    return 0


if __name__ == '__main__':
    sys.exit(main())
