// Shim replacing Awoo's config subsystem. Only the flags the vendored engine
// references remain; NCA validation stays off so no keys/crypto are required.
#pragma once

#include <string>

namespace inst::config {
    inline bool ignoreReqVers = true;
    inline bool validateNCAs = false;
    inline bool overClock = false;
    inline bool gayMode = false;
    inline std::string appDir = "sdmc:/switch/SwitchLoaderReceiver";
}
