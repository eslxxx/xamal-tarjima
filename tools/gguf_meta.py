#!/usr/bin/env python3
"""只解析 GGUF 的 KV 元数据段, 不碰张量。

为什么不用 gguf-py: 它在 _build_tensors 里会按已知量化类型的 block 尺寸去 reshape,
遇到 STQ1_0 (PR #22836 新增的类型) 直接抛 ValueError。我们要的信息全在 KV 段,
所以自己按格式走一遍就够, 顺带避免了对 gguf-py 版本的依赖。

用法: python tools/gguf_meta.py <model.gguf> [--all]
"""
import struct
import sys

# GGUF value types
U8, I8, U16, I16, U32, I32, F32, BOOL, STR, ARR, U64, I64, F64 = range(13)
_FMT = {U8: '<B', I8: '<b', U16: '<H', I16: '<h', U32: '<I', I32: '<i',
        F32: '<f', BOOL: '<?', U64: '<Q', I64: '<q', F64: '<d'}


class Reader:
    def __init__(self, f):
        self.f = f

    def raw(self, n):
        b = self.f.read(n)
        if len(b) != n:
            raise EOFError('文件在元数据段就结束了')
        return b

    def scalar(self, t):
        fmt = _FMT[t]
        return struct.unpack(fmt, self.raw(struct.calcsize(fmt)))[0]

    def string(self):
        n = self.scalar(U64)
        return self.raw(n).decode('utf-8', 'replace')

    def value(self, t):
        if t == STR:
            return self.string()
        if t == ARR:
            et = self.scalar(U32)
            n = self.scalar(U64)
            if et == STR:
                return [self.string() for _ in range(n)]
            if et == ARR:
                return [self.value(ARR) for _ in range(n)]
            fmt = _FMT[et]
            size = struct.calcsize(fmt)
            buf = self.raw(size * n)
            return list(struct.unpack('<' + fmt[1] * n, buf)) if n else []
        return self.scalar(t)


def read_meta(path):
    with open(path, 'rb') as f:
        r = Reader(f)
        if r.raw(4) != b'GGUF':
            raise ValueError('不是 GGUF 文件')
        version = r.scalar(U32)
        n_tensors = r.scalar(U64)
        n_kv = r.scalar(U64)
        kv = {}
        for _ in range(n_kv):
            key = r.string()
            kv[key] = r.value(r.scalar(U32))
        return version, n_tensors, kv


def read_tensor_info(path):
    """继续读 KV 段之后的张量信息表, 返回 [(name, dims, ggml_type, offset)]。

    只读元信息, 不 reshape 数据 —— 正因为 gguf-py 会按已知 block 尺寸去 reshape
    才在 STQ1_0 上炸掉, 而张量的 ggml 类型号恰好是排查「模型和 kernel 版本对不上」
    时最需要的一条信息。
    """
    with open(path, 'rb') as f:
        r = Reader(f)
        if r.raw(4) != b'GGUF':
            raise ValueError('不是 GGUF 文件')
        r.scalar(U32)                       # version
        n_tensors = r.scalar(U64)
        n_kv = r.scalar(U64)
        for _ in range(n_kv):
            r.string()
            r.value(r.scalar(U32))
        infos = []
        for _ in range(n_tensors):
            name = r.string()
            nd = r.scalar(U32)
            dims = [r.scalar(U64) for _ in range(nd)]
            ttype = r.scalar(U32)
            offset = r.scalar(U64)
            infos.append((name, dims, ttype, offset))
        return infos



def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    show_all = '--all' in sys.argv
    version, n_tensors, kv = read_meta(path)

    print(f'gguf 版本   : {version}')
    print(f'张量数      : {n_tensors}')
    print(f'元数据条数  : {len(kv)}')
    print()

    interesting = (
        'general.architecture', 'general.name', 'general.basename',
        'general.file_type', 'general.quantization_version', 'general.size_label',
        'tokenizer.ggml.model', 'tokenizer.ggml.pre',
        'tokenizer.ggml.bos_token_id', 'tokenizer.ggml.eos_token_id',
        'tokenizer.ggml.add_bos_token', 'tokenizer.ggml.add_eos_token',
    )
    for k in interesting:
        if k in kv:
            print(f'{k:44} = {kv[k]}')
    # 架构相关的维度 / 层数 / 上下文长度
    for k in sorted(kv):
        if any(k.endswith(s) for s in ('.block_count', '.context_length',
                                       '.embedding_length', '.attention.head_count',
                                       '.rope.freq_base', '.rope.scaling.type',
                                       '.vocab_size', '.feed_forward_length')):
            print(f'{k:44} = {kv[k]}')

    tmpl = kv.get('tokenizer.chat_template')
    print()
    if tmpl:
        print('=== tokenizer.chat_template ===')
        print(tmpl)
    else:
        print('!! GGUF 里没有 chat_template —— mt_core 会走硬编码的 hunyuan-dense 兜底')

    if show_all:
        print()
        print('=== 全部 key ===')
        for k in sorted(kv):
            v = kv[k]
            if isinstance(v, list):
                v = f'<array len={len(v)}>'
            elif isinstance(v, str) and len(v) > 120:
                v = v[:120] + ' ...'
            print(f'  {k:48} = {v}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
