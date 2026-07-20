// Shim replacing Awoo's util module. Only the helpers the vendored install
// engine actually calls are declared; main.cpp implements them.
#pragma once

#include <string>

namespace inst::util {
    std::string formatUrlString(std::string ourString);
    void initInstallServices();
    void deinitInstallServices();
}
