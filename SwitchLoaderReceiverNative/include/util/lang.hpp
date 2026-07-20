// Shim replacing Awoo's localisation layer. The ""_lang literal just yields the
// key text, which is enough for the status strings the engine emits.
#pragma once

#include <string>
#include <cstddef>

inline std::string operator""_lang(const char* str, std::size_t len) {
    return std::string(str, len);
}

namespace Language {
    inline std::string GetRandomMsg() { return ""; }
}
