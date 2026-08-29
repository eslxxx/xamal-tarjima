cmake_minimum_required(VERSION 3.22)
project(tilmach_engine LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---- llama.cpp (STQ1_0 分支) 以静态库形式内嵌 ----
# 只要 libllama + libggml, 不要它的 examples/tools/server。
set(BUILD_SHARED_LIBS      OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP            OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE         OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL             OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS      OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES   OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER     OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS      OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON     OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/llama.cpp EXCLUDE_FROM_ALL)

# 记录 llama.cpp 的 commit, 编进 mt_engine_info() 里方便线上定位问题
execute_process(
  COMMAND git -C "${CMAKE_CURRENT_SOURCE_DIR}/third_party/llama.cpp" rev-parse --short HEAD
  OUTPUT_VARIABLE MT_LLAMA_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_QUIET)
if(NOT MT_LLAMA_COMMIT)
  set(MT_LLAMA_COMMIT "unknown")
endif()

# ---- libmtcore ----
add_library(mtcore SHARED src/mt_core.cpp)
target_include_directories(mtcore PUBLIC include)
target_link_libraries(mtcore PRIVATE llama ggml)
target_compile_definitions(mtcore PRIVATE MT_LLAMA_COMMIT="${MT_LLAMA_COMMIT}")

# 只导出 MT_API 标记的符号, 避免把 llama.cpp 的符号一起暴露出去
if(NOT WIN32)
  target_compile_options(mtcore PRIVATE -fvisibility=hidden)
  # -fvisibility 只管本目标的编译单元; 静态链进来的 llama/ggml 目标文件
  # 仍会导出自己的符号, 所以还要一份 version script 在链接期收口。
  target_link_options(mtcore PRIVATE
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/mtcore.map")
  set_target_properties(mtcore PROPERTIES LINK_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/mtcore.map")
endif()
if(ANDROID)
  target_link_libraries(mtcore PRIVATE log)
  # 静态链 libc++, 免得 APK 里再带一份 libc++_shared.so
  target_link_options(mtcore PRIVATE -static-libstdc++)
endif()

# ---- mt_cli: 冒烟测试用的命令行工具, adb push 到真机跑 ----
add_executable(mt_cli tools/mt_cli.cpp)
target_link_libraries(mt_cli PRIVATE mtcore)
