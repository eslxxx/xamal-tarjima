#!/usr/bin/env python3
"""核对 mt_core.cpp 里硬编码的特殊 token 字面量是否与 GGUF 词表逐字节一致。

prompt 里的角色标记是手写的十六进制转义 (见 build_prompt 的注释), 一旦写错
模型会收到普通文本而不是特殊 token, 输出质量会莫名变差且极难定位。
所以把这层校验固化成脚本, 每次换模型都跑一遍。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from gguf_meta import read_meta  # noqa: E402

BS = chr(92)  # 反斜杠, 避免在源码里写转义把自己绕晕


def literal_bytes(cpp: str) -> bytes:
    """把相邻的 C 字符串字面量拼接成实际字节序列, 解析 \\xNN 转义。

    手写扫描而不用正则: 字面量里既有反斜杠又有引号, 正则的转义层数太容易写错。
    """
    out = bytearray()
    i, n = 0, len(cpp)
    while i < n:
        if cpp[i] != '"':
            i += 1
            continue
        i += 1  # 跳过开引号
        while i < n and cpp[i] != '"':
            if cpp[i] == BS and i + 1 < n and cpp[i + 1] == 'x':
                j = i + 2
                hexs = ''
                while j < n and len(hexs) < 2 and cpp[j] in '0123456789abcdefABCDEF':
                    hexs += cpp[j]
                    j += 1
                out.append(int(hexs, 16))
                i = j
            elif cpp[i] == BS:
                i += 2  # 本文件里不该有其它转义
            else:
                out += cpp[i].encode('utf-8')
                i += 1
        i += 1  # 跳过闭引号
    return bytes(out)


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else str(
        ROOT / 'models' / 'Hy-MT1.5-1.8B-1.25bit.gguf')
    _, _, kv = read_meta(model)
    toks = kv['tokenizer.ggml.tokens']
    src = (ROOT / 'engine' / 'src' / 'mt_core.cpp').read_text(encoding='utf-8')

    expect = {'kTokBos': 120000, 'kTokUser': 120006, 'kTokAsst': 120007}
    ok = True
    for name, tid in expect.items():
        m = re.search(name + r'\s*=\s*(.+?);', src, re.S)
        if not m:
            print(f'MISS     {name}: 在 mt_core.cpp 里找不到')
            ok = False
            continue
        got, want = literal_bytes(m.group(1)), toks[tid].encode('utf-8')
        same = got == want
        ok &= same
        print(f'{"OK  " if same else "BAD "} {name:9} id={tid}')
        if not same:
            print(f'{"":14}got  = {got!r}')
            print(f'{"":14}want = {want!r}')

    print()
    print(f'eos_token_id = {kv.get("tokenizer.ggml.eos_token_id")} '
          f'({toks[kv["tokenizer.ggml.eos_token_id"]]!r})')
    print(f'bos_token_id = {kv.get("tokenizer.ggml.bos_token_id")} '
          f'({toks[kv["tokenizer.ggml.bos_token_id"]]!r})')
    print(f'add_bos_token = {kv.get("tokenizer.ggml.add_bos_token", "<缺失, llama.cpp 对 BPE 默认 false>")}')
    print()
    print('=> 全部一致' if ok else '=> 有不一致, 必须修!')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
