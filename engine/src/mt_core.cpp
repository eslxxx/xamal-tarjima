// mt_core.cpp — 见 mt_core.h 的设计说明
#include "mt_core.h"

#include "llama.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace {

// ---------------------------------------------------------------- 错误信息
std::string g_last_error;   // mt_init 失败时用 (此时还没有 ctx)

// ---------------------------------------------------------------- UTF-8 边界
// 返回 [0, n) 中「以完整 UTF-8 字符结尾」的最长前缀长度。
// 维文/哈文是 2 字节, 汉字 3 字节, 而单个 token 的字节串经常切在字符中间,
// 直接抛给上层会闪现乱码, 所以必须在这里缓冲。
size_t utf8_safe_len(const char* p, size_t n) {
    if (n == 0) return 0;
    size_t i = n, back = 0;
    while (i > 0 && back < 4) {
        --i; ++back;
        const unsigned char c = static_cast<unsigned char>(p[i]);
        if ((c & 0xC0) == 0x80) continue;          // 续字节, 继续往前找
        size_t need;
        if      ((c & 0x80) == 0x00) need = 1;
        else if ((c & 0xE0) == 0xC0) need = 2;
        else if ((c & 0xF0) == 0xE0) need = 3;
        else if ((c & 0xF8) == 0xF0) need = 4;
        else return n;                             // 非法字节, 别卡住
        return (n - i >= need) ? n : i;
    }
    return n;                                      // 连续 4 个续字节, 数据本身有问题
}

// ---------------------------------------------------------------- 大核探测
// Android 上大小核混合, 把线程铺到小核会明显拖慢 decode。
// 读 cpufreq 的最高频率, 统计频率接近最高值的核数, 再压到 4 以内。
//
// 实测 (骁龙 8s Gen 3 / SM8635, 1×3.0G + 4×2.8G + 3×2.0G, dotprod 版, 同一句):
//     threads=2  5786ms
//     threads=3  4903ms
//     threads=4  4531ms   ← 最快
//     threads=5  4686ms
//     threads=6  5198ms
//     threads=8 18441ms   ← 铺到小核直接崩盘
// 所以宁少勿多: 超过大核数的收益是负的, 而且负得很厉害。
int detect_perf_cores() {
    long best = 0;
    long freqs[64] = {0};
    int  n = 0;
    for (int i = 0; i < 64; ++i) {
        char path[128];
        snprintf(path, sizeof(path),
                 "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq", i);
        FILE* f = fopen(path, "r");
        if (!f) continue;
        long v = 0;
        if (fscanf(f, "%ld", &v) == 1 && v > 0) {
            freqs[n++] = v;
            best = std::max(best, v);
        }
        fclose(f);
    }
    if (n > 0 && best > 0) {
        int big = 0;
        for (int i = 0; i < n; ++i) {
            if (freqs[i] >= best * 85 / 100) ++big;
        }
        return std::max(1, std::min(big, 4));
    }
    const unsigned hw = std::thread::hardware_concurrency();
    return static_cast<int>(std::max(1u, std::min(hw ? hw / 2 : 4u, 4u)));
}

}  // namespace

// ---------------------------------------------------------------- ctx
struct mt_ctx {
    llama_model*        model = nullptr;
    llama_context*      lctx  = nullptr;
    const llama_vocab*  vocab = nullptr;
    int32_t             n_ctx = 0;
    int32_t             n_threads = 0;
    bool                embedded_tmpl = false;
    std::string         tmpl;        // GGUF 内嵌 chat 模板 (可能为空)
    std::string         last_error;
    std::vector<llama_token> tok_buf;
    // 额外的停止 token。本模型的 eos 是 <｜hy_place▁holder▁no▁2｜>(120020),
    // 但 <｜hy_end▁of▁sentence｜> 和 <｜hy_EOT｜> 也可能冒出来, 一起兜住。
    std::vector<llama_token> extra_stops;
};

namespace {

// Hy-MT1.5 的对话标记 (词表 id 见注释, parse_special=true 时按整 token 切)。
// ｜ 是全角竖线 U+FF5C, ▁ 是 U+2581; 都拆成相邻字面量避免十六进制转义贪婪。
const char* const kTokBos  = "<" "\xef\xbd\x9c" "hy_begin" "\xe2\x96\x81" "of" "\xe2\x96\x81" "sentence" "\xef\xbd\x9c" ">";  // 120000
const char* const kTokUser = "<" "\xef\xbd\x9c" "hy_User" "\xef\xbd\x9c" ">";        // 120006
const char* const kTokAsst = "<" "\xef\xbd\x9c" "hy_Assistant" "\xef\xbd\x9c" ">";   // 120007

// 拼 prompt。
//
// ⚠️ 这里**故意不用** llama_chat_apply_template, 因为它对这个模型是错的:
//
//   1. 本模型 GGUF 里的 jinja 同时含 "<｜hy_Assistant｜>" 和 "<｜hy_begin▁of▁sentence｜>",
//      而 llama-chat.cpp 的识别顺序把 HUNYUAN_VL 排在 HUNYUAN_DENSE 前面,
//      于是被误判成 VL。
//   2. VL 分支生成的是 "<BOS>{content}<｜hy_User｜>" —— 角色标记跑到了内容后面,
//      而且完全不加 <｜hy_Assistant｜> 生成提示。喂这种 prompt 模型会胡说,
//      但表面上看起来像是「1.25bit 量化质量差」, 极难定位。
//   3. 即便识别对了, 内置 HUNYUAN_DENSE 分支也不输出 <｜hy_begin▁of▁sentence｜>;
//      而本 GGUF 没有 tokenizer.ggml.add_bos_token, llama.cpp 对 BPE 词表的默认值
//      是 add_bos=false, 所以 tokenize(add_special=true) 也不会补上 BOS。
//
// 按模型自带 jinja (无 system 消息 + add_generation_prompt=true) 展开, 正确形式是:
//   <｜hy_begin▁of▁sentence｜><｜hy_User｜>{content}<｜hy_Assistant｜>
void build_prompt(const char* user_content, std::string& out) {
    out.clear();
    out += kTokBos;
    out += kTokUser;
    out += user_content;
    out += kTokAsst;
}

// 启动时核对 GGUF 里的 jinja 是否还是我们假设的那种形状。
// 将来换模型版本 (比如 Hy-MT2) 如果模板变了, 这里会置 0, App 可以据此提示,
// 而不是默默地用错 prompt。
bool template_matches_assumption(const std::string& tmpl) {
    if (tmpl.empty()) return false;
    const bool has_bos  = tmpl.find(kTokBos)  != std::string::npos;
    const bool has_user = tmpl.find(kTokUser) != std::string::npos;
    const bool has_asst = tmpl.find(kTokAsst) != std::string::npos;
    if (!has_bos || !has_user || !has_asst) return false;
    // 关键: <｜hy_User｜> 必须在 message['content'] **之前** (前缀形式)
    const size_t u = tmpl.find(kTokUser);
    const size_t c = tmpl.find("message['content']", u);
    return c != std::string::npos && c - u < 64;
}

// 把一个特殊 token 的字面量解析成单个 token id; 解析不出单个 id 就返回 -1。
llama_token lookup_special(const llama_vocab* vocab, const char* text) {
    llama_token ids[8];
    const int32_t n = llama_tokenize(vocab, text, static_cast<int32_t>(std::strlen(text)),
                                    ids, 8, /*add_special=*/false, /*parse_special=*/true);
    return n == 1 ? ids[0] : -1;
}

}  // namespace


// ---------------------------------------------------------------- 参数默认值
// 官方推荐: temperature 0.7 / top_p 0.6 / top_k 20 / repetition_penalty 1.05。
// 但翻译任务用贪心解码通常更稳、可复现、也更快, 而且 1.25bit 模型在随机采样下
// 更容易跑偏。所以默认 temperature = 0 (贪心), 官方那组参数保留为可切换项。
extern "C" MT_API mt_params mt_params_default(void) {
    mt_params p;
    p.temperature     = 0.0f;
    p.top_p           = 0.6f;
    p.top_k           = 20;
    p.repeat_penalty  = 1.05f;
    p.repeat_last_n   = 64;
    p.seed            = 0xC0FFEEu;
    p.max_tokens      = 0;    // 0 => 输入 token 数 * 4 + 128
    p.no_repeat_ngram = 6;
    return p;
}

extern "C" MT_API mt_ctx* mt_init(const char* gguf_path, int32_t n_threads, int32_t n_ctx) {
    g_last_error.clear();
    if (!gguf_path || !*gguf_path) {
        g_last_error = "gguf_path 为空";
        return nullptr;
    }

    static bool backend_ready = false;
    if (!backend_ready) {
        llama_backend_init();
        llama_log_set([](ggml_log_level, const char*, void*) {}, nullptr);  // 默认静音
        backend_ready = true;
    }

    auto* c = new mt_ctx();
    c->n_threads = n_threads > 0 ? n_threads : detect_perf_cores();
    // 模型自称 context_length = 4096, 但默认只开 1024:
    //   - 翻译按句子切, 1024 足够, KV cache 省一大截
    //   - 更重要的是这份 GGUF 的 hunyuan-dense.rope.freq_base 被烘成了静态的
    //     11158840 (原始 HF config 是 dynamic NTK, theta=10000), 长 prompt 上
    //     位置编码会偏。短句范围内没问题, 所以上层务必分句, 不要灌长文。
    c->n_ctx     = n_ctx     > 0 ? n_ctx     : 1024;

    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0;                        // STQ1_0 只有 CPU kernel
    // 440MB 权重靠 mmap 按需换入, 不整块读进堆; 不加 mlock —— 手机上锁页会被系统嫌弃。
    // 注意: 这一版 llama.cpp 已经把 use_mmap/use_mlock 合并成 load_mode 枚举。
    mp.load_mode    = LLAMA_LOAD_MODE_MMAP;

    c->model = llama_model_load_from_file(gguf_path, mp);
    if (!c->model) {
        g_last_error = std::string("加载模型失败: ") + gguf_path;
        delete c;
        return nullptr;
    }
    c->vocab = llama_model_get_vocab(c->model);

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx           = static_cast<uint32_t>(c->n_ctx);
    cp.n_batch         = static_cast<uint32_t>(std::min(c->n_ctx, 256));
    cp.n_ubatch        = cp.n_batch;
    cp.n_threads       = c->n_threads;
    cp.n_threads_batch = c->n_threads;

    c->lctx = llama_init_from_model(c->model, cp);
    if (!c->lctx) {
        g_last_error = "创建推理上下文失败 (可能是内存不足)";
        llama_model_free(c->model);
        delete c;
        return nullptr;
    }

    if (const char* t = llama_model_chat_template(c->model, nullptr)) {
        c->tmpl = t;
    }
    c->embedded_tmpl = template_matches_assumption(c->tmpl);

    for (const char* t : {
             "<" "\xef\xbd\x9c" "hy_end" "\xe2\x96\x81" "of" "\xe2\x96\x81" "sentence" "\xef\xbd\x9c" ">",
             "<" "\xef\xbd\x9c" "hy_EOT" "\xef\xbd\x9c" ">",
         }) {
        const llama_token id = lookup_special(c->vocab, t);
        if (id >= 0) c->extra_stops.push_back(id);
    }
    return c;
}

// ---------------------------------------------------------------- 翻译
extern "C" MT_API int32_t mt_translate(mt_ctx* c,
                                       const char* user_content,
                                       const mt_params* params_in,
                                       mt_token_cb on_chunk,
                                       void* user_data,
                                       volatile int32_t* cancel) {
    if (!c || !user_content) {
        if (c) c->last_error = "参数为空";
        return MT_ERR_ARG;
    }
    c->last_error.clear();
    const mt_params p = params_in ? *params_in : mt_params_default();

    std::string prompt;
    build_prompt(user_content, prompt);

    // --- 分词 ---
    std::vector<llama_token>& toks = c->tok_buf;
    toks.assign(prompt.size() + 8, 0);
    int32_t n = llama_tokenize(c->vocab, prompt.data(), static_cast<int32_t>(prompt.size()),
                               toks.data(), static_cast<int32_t>(toks.size()),
                               /*add_special=*/true, /*parse_special=*/true);
    if (n < 0) {                       // 缓冲不够, 按返回的需求量重试一次
        toks.assign(static_cast<size_t>(-n), 0);
        n = llama_tokenize(c->vocab, prompt.data(), static_cast<int32_t>(prompt.size()),
                           toks.data(), static_cast<int32_t>(toks.size()), true, true);
    }
    if (n <= 0) {
        c->last_error = "分词失败";
        return MT_ERR_TOKENIZE;
    }
    toks.resize(static_cast<size_t>(n));

    if (n + 8 >= c->n_ctx) {
        c->last_error = "输入过长, 超出上下文窗口; 上层应先分句";
        return MT_ERR_CTX_FULL;
    }
    // 生成长度上限。
    // 注意别抠得太紧: 这个词表对中文很省 token, 对维文/哈文的阿拉伯字母却很费 ——
    // 实测 zh→ug 一段 70 字的中文, 译文要 200+ token, 按 "prompt×2" 算会被截断。
    // 所以放宽到 ×4 + 128, 真正防跑飞靠下面的 n-gram 复读检测和 n_ctx 上限。
    const int32_t budget  = p.max_tokens > 0 ? p.max_tokens : (n * 4 + 128);
    const int32_t max_new = std::min(budget, c->n_ctx - n - 8);

    // 每次翻译都是独立请求, 清空 KV, 避免上一句污染下一句
    llama_memory_clear(llama_get_memory(c->lctx), true);

    llama_batch pb = llama_batch_get_one(toks.data(), n);
    if (llama_decode(c->lctx, pb) != 0) {
        c->last_error = "prompt 解码失败";
        return MT_ERR_DECODE;
    }

    // --- 采样器 ---
    llama_sampler_chain_params sp = llama_sampler_chain_default_params();
    sp.no_perf = true;
    llama_sampler* smpl = llama_sampler_chain_init(sp);
    if (p.repeat_penalty > 0.0f && p.repeat_penalty != 1.0f && p.repeat_last_n > 0) {
        llama_sampler_chain_add(smpl, llama_sampler_init_penalties(
            llama_vocab_n_tokens(c->vocab), p.repeat_last_n, p.repeat_penalty, 0.0f, 0.0f));
    }
    if (p.temperature <= 0.0f) {
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
    } else {
        if (p.top_k > 0)     llama_sampler_chain_add(smpl, llama_sampler_init_top_k(p.top_k));
        if (p.top_p < 1.0f)  llama_sampler_chain_add(smpl, llama_sampler_init_top_p(p.top_p, 1));
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(p.temperature));
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(p.seed));
    }

    // --- 生成循环 ---
    std::string pending;                 // 未凑成完整 UTF-8 字符的尾巴
    std::vector<llama_token> gen;
    gen.reserve(static_cast<size_t>(max_new));
    int32_t rc = MT_STOPPED_LIMIT;

    for (int32_t step = 0; step < max_new; ++step) {
        if (cancel && *cancel) { rc = MT_CANCELLED; break; }

        llama_token id = llama_sampler_sample(smpl, c->lctx, -1);
        if (llama_vocab_is_eog(c->vocab, id)) { rc = MT_OK; break; }
        if (std::find(c->extra_stops.begin(), c->extra_stops.end(), id)
                != c->extra_stops.end()) {
            rc = MT_OK;
            break;
        }
        llama_sampler_accept(smpl, id);
        gen.push_back(id);

        char piece[512];
        const int32_t np = llama_token_to_piece(c->vocab, id, piece, sizeof(piece),
                                                /*lstrip=*/0, /*special=*/false);
        if (np > 0) {
            pending.append(piece, static_cast<size_t>(np));
            const size_t safe = utf8_safe_len(pending.data(), pending.size());
            if (safe > 0) {
                if (on_chunk) {
                    const std::string chunk = pending.substr(0, safe);
                    if (on_chunk(chunk.c_str(), user_data) != 0) {
                        pending.erase(0, safe);
                        rc = MT_CANCELLED;
                        break;
                    }
                }
                pending.erase(0, safe);
            }
        }

        // n-gram 复读检测: 末尾 k 个 token 在之前出现过 >=2 次就截断。
        // 极低比特模型偶发死循环, 光靠 max_tokens 会让用户干等。
        if (p.no_repeat_ngram > 0) {
            const size_t k = static_cast<size_t>(p.no_repeat_ngram);
            if (gen.size() >= k * 3) {
                const llama_token* tail = gen.data() + gen.size() - k;
                int hits = 0;
                for (size_t s = 0; s + k <= gen.size() - k; ++s) {
                    if (std::memcmp(gen.data() + s, tail, k * sizeof(llama_token)) == 0) {
                        if (++hits >= 2) break;
                    }
                }
                if (hits >= 2) { rc = MT_STOPPED_REPEAT; break; }
            }
        }

        llama_token cur = id;   // 取地址要用局部变量, gen 可能重新分配
        llama_batch nb = llama_batch_get_one(&cur, 1);
        if (llama_decode(c->lctx, nb) != 0) {
            c->last_error = "生成阶段解码失败";
            rc = MT_ERR_DECODE;
            break;
        }
    }

    // 收尾: pending 里剩下的字节一并交出去 (正常结束时通常是空的)
    if (!pending.empty() && on_chunk) {
        on_chunk(pending.c_str(), user_data);
    }

    llama_sampler_free(smpl);
    return rc;
}

// ---------------------------------------------------------------- 释放与查询
extern "C" MT_API void mt_free(mt_ctx* c) {
    if (!c) return;
    if (c->lctx)  llama_free(c->lctx);
    if (c->model) llama_model_free(c->model);
    delete c;
}

extern "C" MT_API const char* mt_last_error(const mt_ctx* c) {
    return c ? c->last_error.c_str() : g_last_error.c_str();
}

extern "C" MT_API const char* mt_engine_info(void) {
    // MT_LLAMA_COMMIT 由 CMake 注入, 便于「关于」页面和线上问题定位
#ifndef MT_LLAMA_COMMIT
#  define MT_LLAMA_COMMIT "unknown"
#endif
    static const std::string info =
        std::string("tilmach mt_core; llama.cpp ") + MT_LLAMA_COMMIT +
        "; quant=STQ1_0(ternary 1.25bit); backend=cpu";
    return info.c_str();
}

extern "C" MT_API int32_t mt_n_ctx(const mt_ctx* c)     { return c ? c->n_ctx : 0; }
extern "C" MT_API int32_t mt_n_threads(const mt_ctx* c) { return c ? c->n_threads : 0; }
extern "C" MT_API int32_t mt_uses_embedded_template(const mt_ctx* c) {
    return (c && c->embedded_tmpl) ? 1 : 0;
}




