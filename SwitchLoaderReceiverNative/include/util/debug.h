// Shim replacing Awoo's debug logger. LOG_DEBUG becomes a no-op; printBytes is
// an empty inline. Keeps the vendored engine compiling without nxlink/debug.c.
#pragma once

#define LOG_DEBUG(...) ((void)0)

#ifdef __cplusplus
#include <cstddef>
static inline void printBytes(const void*, std::size_t, bool) {}
#endif
