// mt_cli.cpp — mt_core 的冒烟测试工具。
//
// 用途: adb push 到真机, 在目标机型上直接验证
//   1. STQ1_0 模型能否加载
//   2. 三语互译输出是否正常 (含哈萨克语落到哪套文字)
//   3. 端到端速度和峰值内存
//
// 用法:
//   mt_cli <model.gguf> <目标语言中文名或英文名> <待翻译文本> [--threads N] [--ctx N] [--official]
// 例:
//   mt_cli model.gguf 维吾尔语 "今天天气很好"
//   mt_cli model.gguf Kazakh   "ياخشىمۇسىز"   // 维->哈, 走英文指令模板
#include "mt_core.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

int on_chunk(const char* s, void* /*user*/) {
    std::fputs(s, stdout);
    std::fflush(stdout);
    return 0;
}

// 目标语言名里含非 ASCII 就当成中文名 → 用中文指令模板 (ZH<=>XX);
// 全 ASCII 当成英文名 → 用英文指令模板 (XX<=>XX, 不含中文)。
// 官方规则: 中文指令配中文语言全名, 英文指令配英文语言全名。
bool is_ascii(const std::string& s) {
    for (unsigned char ch : s) if (ch > 0x7F) return false;
    return true;
}

std::string build_user_content(const std::string& target_lang, const std::string& text) {
    if (is_ascii(target_lang)) {
        return "Translate the following segment into " + target_lang +
               ", without additional explanation.\n\n" + text;
    }
    return "将以下文本翻译为" + target_lang +
           "，注意只需要输出翻译后的结果，不要额外解释：\n\n" + text;
}

const char* rc_name(int rc) {
    switch (rc) {
        case MT_OK:             return "OK";
        case MT_CANCELLED:      return "CANCELLED";
        case MT_STOPPED_LIMIT:  return "STOPPED_LIMIT(撞到 max_tokens)";
        case MT_STOPPED_REPEAT: return "STOPPED_REPEAT(检测到复读)";
        case MT_ERR_CTX_FULL:   return "ERR_CTX_FULL(输入过长)";
        case MT_ERR_TOKENIZE:   return "ERR_TOKENIZE";
        case MT_ERR_DECODE:     return "ERR_DECODE";
        case MT_ERR_ARG:        return "ERR_ARG";
        default:                return "UNKNOWN";
    }
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 4) {
        std::fprintf(stderr,
            "用法: mt_cli <model.gguf> <目标语言名> <文本> [--threads N] [--ctx N] [--official]\n"
            "  目标语言名: 中文全名(维吾尔语/哈萨克语/中文) 走中文指令模板\n"
            "              英文全名(Uyghur/Kazakh/Chinese) 走英文指令模板\n"
            "  --official : 用官方推荐采样参数 (temp 0.7/top_p 0.6/top_k 20), 默认贪心\n");
        return 2;
    }
    const char* model_path = argv[1];
    const std::string target = argv[2];
    const std::string text   = argv[3];

    int  threads = 0, n_ctx = 0;
    bool official = false;
    for (int i = 4; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--threads") && i + 1 < argc) threads = std::atoi(argv[++i]);
        else if (!std::strcmp(argv[i], "--ctx") && i + 1 < argc) n_ctx = std::atoi(argv[++i]);
        else if (!std::strcmp(argv[i], "--official")) official = true;
    }

    std::printf("engine  : %s\n", mt_engine_info());
    const auto t_load0 = std::chrono::steady_clock::now();
    mt_ctx* ctx = mt_init(model_path, threads, n_ctx);
    if (!ctx) {
        std::fprintf(stderr, "mt_init 失败: %s\n", mt_last_error(nullptr));
        return 1;
    }
    const double load_ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - t_load0).count();

    std::printf("load    : %.0f ms\n", load_ms);
    std::printf("threads : %d\n", mt_n_threads(ctx));
    std::printf("n_ctx   : %d\n", mt_n_ctx(ctx));
    std::printf("template: %s\n",
                mt_uses_embedded_template(ctx)
                    ? "GGUF jinja 与硬编码假设一致"
                    : "!! GGUF jinja 与假设不符, 输出可能不对");

    mt_params p = mt_params_default();
    if (official) p.temperature = 0.7f;

    const std::string user_content = build_user_content(target, text);
    std::printf("--------\n原文    : %s\n译文    : ", text.c_str());
    std::fflush(stdout);

    const auto t0 = std::chrono::steady_clock::now();
    const int rc = mt_translate(ctx, user_content.c_str(), &p, on_chunk, nullptr, nullptr);
    const double ms = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - t0).count();

    std::printf("\n--------\n结果    : %s (%d)\n耗时    : %.0f ms\n", rc_name(rc), rc, ms);
    if (rc < 0 && rc != MT_CANCELLED && rc != MT_STOPPED_LIMIT && rc != MT_STOPPED_REPEAT) {
        std::fprintf(stderr, "错误    : %s\n", mt_last_error(ctx));
    }
    mt_free(ctx);
    return rc == MT_OK ? 0 : 1;
}
