// Shim replacing Awoo's install-progress page. The vendored engine calls these
// to report progress; main.cpp implements them by updating the on-screen
// ScreenState and re-rendering.
#pragma once

#include <string>

namespace inst::ui::instPage {
    void setInstInfoText(std::string ourText);
    void setInstBarPerc(double ourPercent);
    void setTopInstInfoText(std::string ourText);
    void loadInstallScreen();
    void loadMainMenu();
}
