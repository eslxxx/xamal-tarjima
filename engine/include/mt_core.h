// mt_core.h — Tilmach 翻译推理核对外 C ABI
//
// 设计原则:
//   1. 只暴露 C ABI, 便于 dart:ffi / JNI / Swift 直接调用, 不暴露任何 C++ 类型。
//   2. 保持极薄: 只做「加载模型 / 套 chat 模板 / 流式生成 / 取消」。
//      语言表和 prompt 文案放在 Dart 层, 方便迭代与单测。
//   3. 单个 mt_ctx 不是线程安全的; 调用方保证同一时刻只有一个 mt_translate 在跑。
//      (App 里模型是单例, 翻译跑在专用 isolate, 天然满足。)
#ifndef TILMACH_MT_CORE_H
#define TILMACH_MT_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  define MT_API __declspec(dllexport)
#else
#  define MT_API __attribute__((visibility("default")))
#endif

typedef struct mt_ctx mt_ctx;

// mt_translate 的返回码
enum {
    MT_OK             =  0,  // 正常生成到 EOS
    MT_ERR_ARG        = -1,  // 参数非法
    MT_ERR_TOKENIZE   = -2,  // 分词失败
    MT_ERR_CTX_FULL   = -3,  // 输入超出 n_ctx
    MT_ERR_DECODE     = -4,  // llama_decode 失败
    MT_CANCELLED      = -5,  // 被 cancel 标志中断
    MT_STOPPED_LIMIT  = -6,  // 撞到 max_tokens 上限 (低比特模型跑飞的兜底)
    MT_STOPPED_REPEAT = -7,  // 检测到 n-gram 循环, 主动截断
};

// 生成参数。全部字段填 0 交给 mt_params_default() 取默认值。
typedef struct mt_params {
    float   temperature;      // 0 = 贪心解码
    float   top_p;
    int32_t top_k;
    float   repeat_penalty;
    int32_t repeat_last_n;
    uint32_t seed;
    int32_t max_tokens;       // 硬上限; <=0 表示用 (输入 token 数 * 4 + 128)
    int32_t no_repeat_ngram;  // 循环检测的 n-gram 长度; <=0 关闭
} mt_params;

MT_API mt_params mt_params_default(void);

// 流式回调: 每次拿到一段**完整 UTF-8** 的新文本时触发。
// mt_core 内部会缓冲不完整的多字节序列 —— 维文/哈文/汉字都是多字节,
// 单个 token 经常切在字符中间, 直接往上抛会产生乱码。
// 返回非 0 表示调用方要求停止生成 (等价于 cancel)。
typedef int (*mt_token_cb)(const char* utf8_chunk, void* user_data);

// 加载模型。失败返回 NULL, 具体原因用 mt_last_error(NULL) 取。
//   gguf_path : 必须是真实文件路径 (要能 mmap), 不能是 asset / zip 内路径
//   n_threads : <=0 时自动取「大核数量」的估计值
//   n_ctx     : <=0 时默认 1024。翻译都是短句, 没必要开大, 省 KV cache
MT_API mt_ctx* mt_init(const char* gguf_path, int32_t n_threads, int32_t n_ctx);

// 执行一次翻译。user_content 是**已经拼好的用户消息正文**
// (例如 "将以下文本翻译为维吾尔语，注意只需要输出翻译后的结果，不要额外解释：\n\n你好")，
// chat 模板由本函数内部套上。
//
//   cancel : 可为 NULL。非 NULL 时, 生成循环每步检查 *cancel, 非 0 立即中断。
//   返回值 : 见上面的 MT_* 枚举。<0 且非 MT_CANCELLED/MT_STOPPED_* 时视为错误。
MT_API int32_t mt_translate(mt_ctx* ctx,
                            const char* user_content,
                            const mt_params* params,
                            mt_token_cb on_chunk,
                            void* user_data,
                            volatile int32_t* cancel);

// 释放。传 NULL 是安全的。
MT_API void mt_free(mt_ctx* ctx);

// 最近一次错误信息。ctx 可为 NULL (取全局错误, 用于 mt_init 失败的场景)。
// 返回的指针在下一次同一 ctx 上的调用前有效。
MT_API const char* mt_last_error(const mt_ctx* ctx);

// 引擎信息 (llama.cpp commit / 是否含 STQ1_0 / chat 模板走的哪条路径)，
// 用于「关于」页面和 manifest 兼容性判断。
MT_API const char* mt_engine_info(void);

// 已加载模型的元信息, 便于 UI 显示和排错。
MT_API int32_t mt_n_ctx(const mt_ctx* ctx);
MT_API int32_t mt_n_threads(const mt_ctx* ctx);
// prompt 格式是硬编码的 (原因见 mt_core.cpp 里 build_prompt 的注释)。
// 这个函数返回 1 表示 GGUF 里的 jinja 模板仍然符合我们硬编码时的假设;
// 返回 0 表示模型换了模板 —— 此时输出可能不对, App 应该提示用户升级。
MT_API int32_t mt_uses_embedded_template(const mt_ctx* ctx);

#ifdef __cplusplus
}
#endif
#endif  // TILMACH_MT_CORE_H
