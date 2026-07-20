#include <switch.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <string>
#include <vector>

// Vendored Awoo install engine
#include "install/usb_nsp.hpp"
#include "install/install_nsp.hpp"
#include "install/usb_xci.hpp"
#include "install/install_xci.hpp"
#include "data/buffered_placeholder_writer.hpp"
#include "util/util.hpp"
#include "nx/ipc/es.h"
#include "nx/ipc/ns_ext.h"

namespace {

constexpr u16 kVendorId = 0x057E;
constexpr u16 kProductId = 0x3000;
constexpr size_t kUsbBufferSize = 0x100000;             // 1 MiB page-aligned USB DMA buffer
constexpr u32 kScreenWidth = 1280;
constexpr u32 kScreenHeight = 720;

// ---- Tinfoil USB protocol magics ----
constexpr u32 kTulMagic = 0x304C5554; // "TUL0" - Tinfoil Usb List 0 (PC -> Switch, once)
constexpr u32 kTucMagic = 0x30435554; // "TUC0" - Tinfoil Usb Command 0 (both directions)

enum class ScreenMode {
    Waiting,
    Queue,
    Receiving,
    Complete,
    Error,
};

struct ScreenState {
    ScreenMode mode = ScreenMode::Waiting;
    std::string title = "Ready to receive";
    std::string detail = "Choose files in SwitchLoader on your Mac, then send to this receiver.";
    std::string fileName;
    std::string footer = "+ EXIT    X CHANGE INSTALL TARGET";
    bool systemMemory = false;   // false = SD card, true = internal (NAND) storage
    u64 received = 0;
    u64 total = 0;
    size_t fileIndex = 0;
    size_t fileCount = 0;
    int progress = 0;
};

using Glyph = std::array<u8, 7>;

const Glyph& glyphFor(char input) {
    static const Glyph blank{0, 0, 0, 0, 0, 0, 0};
    static const Glyph unknown{0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04};
    static const Glyph A{0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11};
    static const Glyph B{0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E};
    static const Glyph C{0x0F, 0x10, 0x10, 0x10, 0x10, 0x10, 0x0F};
    static const Glyph D{0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E};
    static const Glyph E{0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F};
    static const Glyph F{0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10};
    static const Glyph G{0x0F, 0x10, 0x10, 0x13, 0x11, 0x11, 0x0F};
    static const Glyph H{0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11};
    static const Glyph I{0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E};
    static const Glyph J{0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0E};
    static const Glyph K{0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11};
    static const Glyph L{0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F};
    static const Glyph M{0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11};
    static const Glyph N{0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11};
    static const Glyph O{0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E};
    static const Glyph P{0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10};
    static const Glyph Q{0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D};
    static const Glyph R{0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11};
    static const Glyph S{0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E};
    static const Glyph T{0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04};
    static const Glyph U{0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E};
    static const Glyph V{0x11, 0x11, 0x11, 0x11, 0x0A, 0x0A, 0x04};
    static const Glyph W{0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11};
    static const Glyph X{0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11};
    static const Glyph Y{0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04};
    static const Glyph Z{0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F};
    static const Glyph n0{0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E};
    static const Glyph n1{0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E};
    static const Glyph n2{0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F};
    static const Glyph n3{0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E};
    static const Glyph n4{0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02};
    static const Glyph n5{0x1F, 0x10, 0x10, 0x1E, 0x01, 0x01, 0x1E};
    static const Glyph n6{0x0E, 0x10, 0x10, 0x1E, 0x11, 0x11, 0x0E};
    static const Glyph n7{0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08};
    static const Glyph n8{0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E};
    static const Glyph n9{0x0E, 0x11, 0x11, 0x0F, 0x01, 0x01, 0x0E};
    static const Glyph dot{0, 0, 0, 0, 0, 0x0C, 0x0C};
    static const Glyph comma{0, 0, 0, 0, 0, 0x0C, 0x08};
    static const Glyph colon{0, 0x0C, 0x0C, 0, 0x0C, 0x0C, 0};
    static const Glyph dash{0, 0, 0, 0x1F, 0, 0, 0};
    static const Glyph plus{0, 0x04, 0x04, 0x1F, 0x04, 0x04, 0};
    static const Glyph slash{0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10};
    static const Glyph percent{0x19, 0x19, 0x02, 0x04, 0x08, 0x13, 0x13};
    static const Glyph lparen{0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02};
    static const Glyph rparen{0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08};

    char c = input;
    if (c >= 'a' && c <= 'z') {
        c = static_cast<char>(c - 'a' + 'A');
    }

    switch (c) {
        case ' ': return blank;
        case 'A': return A;
        case 'B': return B;
        case 'C': return C;
        case 'D': return D;
        case 'E': return E;
        case 'F': return F;
        case 'G': return G;
        case 'H': return H;
        case 'I': return I;
        case 'J': return J;
        case 'K': return K;
        case 'L': return L;
        case 'M': return M;
        case 'N': return N;
        case 'O': return O;
        case 'P': return P;
        case 'Q': return Q;
        case 'R': return R;
        case 'S': return S;
        case 'T': return T;
        case 'U': return U;
        case 'V': return V;
        case 'W': return W;
        case 'X': return X;
        case 'Y': return Y;
        case 'Z': return Z;
        case '0': return n0;
        case '1': return n1;
        case '2': return n2;
        case '3': return n3;
        case '4': return n4;
        case '5': return n5;
        case '6': return n6;
        case '7': return n7;
        case '8': return n8;
        case '9': return n9;
        case '.': return dot;
        case ',': return comma;
        case ':': return colon;
        case '-': return dash;
        case '+': return plus;
        case '/': return slash;
        case '%': return percent;
        case '(': return lparen;
        case ')': return rparen;
        default: return unknown;
    }
}

class SwitchLoaderUI {
public:
    bool initialize() {
        framebufferCreate(&framebuffer, nwindowGetDefault(), kScreenWidth, kScreenHeight, PIXEL_FORMAT_RGBA_8888, 2);
        framebufferMakeLinear(&framebuffer);
        initialized = true;
        return true;
    }

    void close() {
        if (initialized) {
            framebufferClose(&framebuffer);
            initialized = false;
        }
    }

    void render(const ScreenState& state) {
        if (!initialized) {
            return;
        }

        u32 stride = 0;
        pixels = static_cast<u32*>(framebufferBegin(&framebuffer, &stride));
        stridePixels = stride / sizeof(u32);
        frame += 1;

        fillRect(0, 0, kScreenWidth, kScreenHeight, color(24, 24, 25));
        fillRect(0, 0, kScreenWidth, 96, color(30, 30, 31));
        fillRect(0, 95, kScreenWidth, 2, color(54, 54, 56));

        drawAppIcon(42, 22);
        drawText("SWITCHLOADER", 116, 24, 4, color(225, 225, 226), 500);
        drawText("USB RECEIVER FOR APPLE SILICON", 118, 60, 2, color(155, 155, 160), 520);

        drawPill(760, 26, 214, 46, "USB RECEIVE", color(13, 132, 246), color(246, 248, 255));
        drawPill(1022, 26, 176, 46, statusText(state.mode), statusColor(state.mode), color(235, 235, 238));

        drawPanel(40, 126, 390, 548);
        drawText("RECEIVE OVER USB", 72, 160, 3, color(235, 235, 238), 320);
        drawStep(1, 76, 220, "OPEN RECEIVER", "KEEP THIS SCREEN OPEN");
        drawStep(2, 76, 302, "CONNECT USB", "USE A DATA CABLE");
        drawStep(3, 76, 384, "SEND FROM MAC", "SWITCHLOADER WILL FIND THIS APP");
        drawStep(4, 76, 466, "FILES SAVE TO SD", "SWITCHLOADERRECEIVER/INBOX");
        drawText(state.footer.c_str(), 72, 622, 2, color(150, 150, 154), 310);

        drawPanel(462, 126, 778, 548);
        drawHeroDevice(814, 220);
        drawText(state.title.c_str(), 514, 160, 4, color(240, 240, 242), 660);
        drawText(state.detail.c_str(), 516, 210, 2, color(165, 165, 170), 610);

        if (state.mode == ScreenMode::Queue || state.mode == ScreenMode::Receiving || state.mode == ScreenMode::Complete) {
            char queueLine[96]{};
            std::snprintf(queueLine, sizeof(queueLine), "%zu FILE%s IN QUEUE", state.fileCount, state.fileCount == 1 ? "" : "S");
            drawText(queueLine, 516, 292, 3, color(225, 225, 228), 610);
        }

        if (!state.fileName.empty()) {
            drawText("CURRENT FILE", 516, 354, 2, color(120, 205, 228), 260);
            drawText(state.fileName.c_str(), 516, 384, 3, color(236, 236, 238), 620);
        }

        if (state.mode == ScreenMode::Receiving || state.mode == ScreenMode::Complete) {
            drawProgress(516, 482, 642, 24, state.progress);
            char percentLine[128]{};
            if (state.total > 0) {
                std::snprintf(
                    percentLine,
                    sizeof(percentLine),
                    "%d%%  %llu / %llu BYTES",
                    state.progress,
                    static_cast<unsigned long long>(state.received),
                    static_cast<unsigned long long>(state.total)
                );
            } else {
                std::snprintf(percentLine, sizeof(percentLine), "%d%%", state.progress);
            }
            drawText(percentLine, 516, 526, 2, color(170, 170, 176), 642);
        }

        if (state.mode == ScreenMode::Waiting) {
            drawText("WAITING FOR THE MAC APP", 516, 300, 3, color(120, 205, 228), 642);
            drawText("CHOOSE FILES, THEN PRESS SEND TO SWITCHLOADER RECEIVER.", 516, 348, 2, color(178, 178, 184), 642);
            char targetLine[80]{};
            std::snprintf(targetLine, sizeof(targetLine), "INSTALL TARGET: %s", state.systemMemory ? "SYSTEM MEMORY" : "SD CARD");
            drawText(targetLine, 516, 396, 3, color(226, 226, 229), 642);
            drawText("PRESS X TO CHANGE INSTALL TARGET", 516, 444, 2, color(150, 150, 156), 642);
        }

        framebufferEnd(&framebuffer);
    }

private:
    Framebuffer framebuffer{};
    bool initialized = false;
    u32* pixels = nullptr;
    u32 stridePixels = 0;
    u32 frame = 0;

    static u32 color(u8 r, u8 g, u8 b) {
        return RGBA8_MAXALPHA(r, g, b);
    }

    static const char* statusText(ScreenMode mode) {
        switch (mode) {
            case ScreenMode::Waiting: return "WAITING";
            case ScreenMode::Queue: return "QUEUE READY";
            case ScreenMode::Receiving: return "RECEIVING";
            case ScreenMode::Complete: return "COMPLETE";
            case ScreenMode::Error: return "ERROR";
        }
        return "READY";
    }

    static u32 statusColor(ScreenMode mode) {
        switch (mode) {
            case ScreenMode::Waiting: return color(68, 68, 70);
            case ScreenMode::Queue: return color(30, 82, 145);
            case ScreenMode::Receiving: return color(13, 132, 246);
            case ScreenMode::Complete: return color(28, 92, 44);
            case ScreenMode::Error: return color(128, 40, 44);
        }
        return color(68, 68, 70);
    }

    void putPixel(int x, int y, u32 value) {
        if (x < 0 || y < 0 || x >= static_cast<int>(kScreenWidth) || y >= static_cast<int>(kScreenHeight)) {
            return;
        }
        pixels[y * stridePixels + x] = value;
    }

    void fillRect(int x, int y, int width, int height, u32 value) {
        const int startX = std::max(0, x);
        const int startY = std::max(0, y);
        const int endX = std::min<int>(kScreenWidth, x + width);
        const int endY = std::min<int>(kScreenHeight, y + height);

        for (int row = startY; row < endY; row += 1) {
            u32* line = pixels + row * stridePixels;
            for (int column = startX; column < endX; column += 1) {
                line[column] = value;
            }
        }
    }

    void fillRoundedRect(int x, int y, int width, int height, int radius, u32 value) {
        fillRect(x + radius, y, width - radius * 2, height, value);
        fillRect(x, y + radius, width, height - radius * 2, value);

        for (int cy = 0; cy < radius; cy += 1) {
            for (int cx = 0; cx < radius; cx += 1) {
                const int dx = radius - cx;
                const int dy = radius - cy;
                if (dx * dx + dy * dy <= radius * radius) {
                    putPixel(x + cx, y + cy, value);
                    putPixel(x + width - cx - 1, y + cy, value);
                    putPixel(x + cx, y + height - cy - 1, value);
                    putPixel(x + width - cx - 1, y + height - cy - 1, value);
                }
            }
        }
    }

    void strokeRect(int x, int y, int width, int height, u32 value) {
        fillRect(x, y, width, 2, value);
        fillRect(x, y + height - 2, width, 2, value);
        fillRect(x, y, 2, height, value);
        fillRect(x + width - 2, y, 2, height, value);
    }

    void drawPanel(int x, int y, int width, int height) {
        fillRoundedRect(x, y, width, height, 18, color(29, 29, 31));
        strokeRect(x, y, width, height, color(54, 54, 57));
    }

    void drawText(const char* text, int x, int y, int scale, u32 value, int maxWidth) {
        int cursorX = x;
        int cursorY = y;
        const int advance = 6 * scale;

        for (const char* cursor = text; *cursor != '\0'; cursor += 1) {
            if (*cursor == '\n') {
                cursorX = x;
                cursorY += 9 * scale;
                continue;
            }

            if (cursorX + 5 * scale > x + maxWidth) {
                break;
            }

            const Glyph& glyph = glyphFor(*cursor);
            for (int row = 0; row < 7; row += 1) {
                for (int column = 0; column < 5; column += 1) {
                    if ((glyph[row] >> (4 - column)) & 1) {
                        fillRect(cursorX + column * scale, cursorY + row * scale, scale, scale, value);
                    }
                }
            }

            cursorX += advance;
        }
    }

    void drawPill(int x, int y, int width, int height, const char* text, u32 background, u32 foreground) {
        fillRoundedRect(x, y, width, height, height / 2, background);
        drawText(text, x + 24, y + 15, 2, foreground, width - 40);
    }

    void drawStep(int number, int x, int y, const char* title, const char* detail) {
        fillRoundedRect(x, y, 46, 46, 23, color(13, 132, 246));
        char numberText[4]{};
        std::snprintf(numberText, sizeof(numberText), "%d", number);
        drawText(numberText, x + 18, y + 14, 2, color(245, 248, 255), 20);
        drawText(title, x + 66, y + 2, 2, color(226, 226, 229), 260);
        drawText(detail, x + 66, y + 30, 2, color(150, 150, 156), 270);
    }

    void drawProgress(int x, int y, int width, int height, int progress) {
        fillRoundedRect(x, y, width, height, height / 2, color(54, 54, 55));
        const int clamped = std::max(0, std::min(100, progress));
        const int fillWidth = std::max(height, (width * clamped) / 100);
        fillRoundedRect(x, y, fillWidth, height, height / 2, color(13, 132, 246));
    }

    void drawAppIcon(int x, int y) {
        fillRoundedRect(x, y, 54, 54, 12, color(12, 14, 16));
        strokeRect(x, y, 54, 54, color(57, 58, 62));
        fillRoundedRect(x + 14, y + 10, 26, 34, 8, color(24, 40, 50));
        fillRoundedRect(x + 6, y + 15, 11, 24, 6, color(20, 148, 177));
        fillRoundedRect(x + 37, y + 15, 11, 24, 6, color(255, 89, 100));
        fillRect(x + 21, y + 18, 12, 3, color(120, 205, 228));
        fillRect(x + 21, y + 27, 12, 3, color(120, 205, 228));
        fillRect(x + 21, y + 36, 12, 3, color(120, 205, 228));
    }

    void drawHeroDevice(int centerX, int y) {
        const int bob = static_cast<int>((frame / 18) % 2);
        fillRoundedRect(centerX - 126, y + 36 + bob, 252, 126, 28, color(42, 44, 48));
        fillRoundedRect(centerX - 94, y + 54 + bob, 188, 90, 14, color(12, 13, 15));
        fillRoundedRect(centerX - 170, y + 44 + bob, 48, 110, 20, color(25, 138, 180));
        fillRoundedRect(centerX + 122, y + 44 + bob, 48, 110, 20, color(234, 78, 91));
        fillRoundedRect(centerX - 154, y + 68 + bob, 16, 16, 8, color(228, 245, 250));
        fillRoundedRect(centerX + 138, y + 68 + bob, 16, 16, 8, color(255, 238, 240));
        fillRect(centerX - 54, y + 92 + bob, 108, 8, color(13, 132, 246));
        fillRect(centerX - 34, y + 112 + bob, 68, 8, color(120, 205, 228));
    }
};

SwitchLoaderUI* activeUI = nullptr;
ScreenState* activeState = nullptr;
PadState* activePad = nullptr;

bool userRequestedExit() {
    if (activePad == nullptr) {
        return false;
    }
    padUpdate(activePad);
    const u64 kDown = padGetButtonsDown(activePad);
    // While idle on the waiting screen, X toggles the install destination.
    if (activeState != nullptr && activeState->mode == ScreenMode::Waiting && (kDown & HidNpadButton_X)) {
        activeState->systemMemory = !activeState->systemMemory;
    }
    return (kDown & HidNpadButton_Plus) != 0;
}

void renderActiveScreen() {
    if (activeUI != nullptr && activeState != nullptr) {
        activeUI->render(*activeState);
    }
}

// ---------------------------------------------------------------------------
// Tinfoil USB protocol wire structures
// ---------------------------------------------------------------------------

// PC -> Switch, sent once when the Mac app starts a transfer.
struct TinfoilListHeader {
    u32 magic;          // "TUL0"
    u32 titleListSize;  // bytes of newline-separated file names that follow
    u64 padding;
} NX_PACKED;
static_assert(sizeof(TinfoilListHeader) == 0x10, "TinfoilListHeader must be 0x10");

// Command header, exchanged both directions (0x20 bytes).
struct UsbCmdHeader {
    u32 magic;          // "TUC0"
    u8 type;            // 0 = REQUEST (Switch -> PC), 1 = RESPONSE (PC -> Switch)
    u8 padding[3];
    u32 cmdId;          // 0 = exit, 1 = file range
    u64 dataSize;       // number of payload bytes that follow this header
    u8 reserved[0xC];
} NX_PACKED;
static_assert(sizeof(UsbCmdHeader) == 0x20, "UsbCmdHeader must be 0x20");

// Body of a file-range request (0x20 bytes), followed by nameLen name bytes.
struct FileRangeCmdHeader {
    u64 size;
    u64 offset;
    u64 nameLen;
    u64 padding;
} NX_PACKED;
static_assert(sizeof(FileRangeCmdHeader) == 0x20, "FileRangeCmdHeader must be 0x20");

// ---------------------------------------------------------------------------
// Low-level USB helpers
// ---------------------------------------------------------------------------

// Responsive blocking write. Small headers only, so a plain blocking write is
// fine: the Mac app is actively servicing us whenever we send a command.
bool usbWriteExact(const void* src, size_t size) {
    const u8* cursor = static_cast<const u8*>(src);
    size_t remaining = size;
    while (remaining > 0) {
        const size_t written = usbCommsWrite(cursor, remaining);
        if (written == 0) {
            return false;
        }
        cursor += written;
        remaining -= written;
    }
    return true;
}

// Single page-aligned DMA buffer that ALL USB reads land in. libnx's async USB
// read (usbCommsReadAsync -> usbDsEndpoint_PostBufferAsync) requires the buffer
// to be 0x1000-aligned; posting an unaligned buffer fails to arm the endpoint,
// which manifests on the host as a timeout on the very first transfer. So we
// never read straight into caller structs -- we read here, then copy out.
u8* g_rxBuffer = nullptr;

// Reads one URB (up to min(size, kUsbBufferSize) bytes) into g_rxBuffer, keeping
// the UI responsive and honouring the + exit button. Returns false on user exit
// or fatal error; on success `transferred` holds the byte count sitting in
// g_rxBuffer.
bool usbReadRaw(size_t size, size_t& transferred) {
    transferred = 0;
    const size_t request = std::min(size, kUsbBufferSize);

    while (appletMainLoop()) {
        if (userRequestedExit()) {
            return false;
        }

        u32 urbId = 0;
        Result rc = usbCommsReadAsync(g_rxBuffer, request, &urbId, 0);
        if (R_FAILED(rc)) {
            renderActiveScreen();
            svcSleepThread(2'000'000);
            continue;
        }

        Event* completionEvent = usbCommsGetReadCompletionEvent(0);
        bool completed = false;
        while (appletMainLoop()) {
            if (userRequestedExit()) {
                return false;
            }
            rc = eventWait(completionEvent, 16'000'000);
            if (R_SUCCEEDED(rc)) {
                eventClear(completionEvent);
                completed = true;
                break;
            }
            renderActiveScreen();
        }
        if (!completed) {
            return false;
        }

        u32 got = 0;
        rc = usbCommsGetReadResult(urbId, &got, 0);
        if (R_FAILED(rc)) {
            renderActiveScreen();
            svcSleepThread(2'000'000);
            continue;
        }
        if (got == 0) {
            renderActiveScreen();
            continue;
        }

        transferred = got;
        return true;
    }

    return false;
}

// Reads exactly `size` bytes into an arbitrary (possibly unaligned) destination
// by bouncing through the aligned g_rxBuffer. False on exit / error.
bool usbReadExact(void* destination, size_t size) {
    auto* cursor = static_cast<u8*>(destination);
    size_t received = 0;
    while (received < size) {
        size_t got = 0;
        if (!usbReadRaw(size - received, got)) {
            return false;
        }
        std::memcpy(cursor + received, g_rxBuffer, got);
        received += got;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Tinfoil command helpers
// ---------------------------------------------------------------------------

// Tells the PC the session is finished (Awoo/Tinfoil expects this).
bool sendExitCommand() {
    UsbCmdHeader cmd{};
    cmd.magic = kTucMagic;
    cmd.type = 0;
    cmd.cmdId = 0; // exit
    cmd.dataSize = 0;
    return usbWriteExact(&cmd, sizeof(cmd));
}

std::string lowercased(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

bool endsWith(const std::string& value, const char* suffix) {
    const size_t len = std::strlen(suffix);
    return value.size() >= len && value.compare(value.size() - len, len, suffix) == 0;
}

bool isXciName(const std::string& name) { return endsWith(lowercased(name), ".xci"); }
bool isNspName(const std::string& name) { return endsWith(lowercased(name), ".nsp"); }

std::string safeDisplayName(const std::string& name) {
    const size_t slash = name.find_last_of("/\\");
    return (slash == std::string::npos) ? name : name.substr(slash + 1);
}

// ---------------------------------------------------------------------------
// Transfer stages
// ---------------------------------------------------------------------------

// Waits for the Mac app to push the TUL0 header + file list, then parses names.
// Returns false on user exit (mode stays Waiting) or protocol error (mode Error).
bool readTitleList(std::vector<std::string>& titles, ScreenState& state) {
    state.mode = ScreenMode::Waiting;
    state.title = "Ready to receive";
    state.detail = "Choose files in SwitchLoader on your Mac, then send to this receiver.";
    state.fileName.clear();
    state.progress = 0;
    renderActiveScreen();

    TinfoilListHeader header{};
    if (!usbReadExact(&header, sizeof(header))) {
        return false; // user exit or USB dropped while waiting
    }
    if (header.magic != kTulMagic) {
        state.mode = ScreenMode::Error;
        state.title = "Unexpected data";
        state.detail = "The Mac did not start with a Tinfoil file list.";
        return false;
    }

    std::string listBuffer(header.titleListSize, '\0');
    if (header.titleListSize != 0 && !usbReadExact(listBuffer.data(), header.titleListSize)) {
        state.mode = ScreenMode::Error;
        state.title = "File list failed";
        state.detail = "Could not read the file list from the Mac.";
        return false;
    }

    titles.clear();
    std::string current;
    for (const char character : listBuffer) {
        if (character == '\n') {
            if (!current.empty()) titles.push_back(current);
            current.clear();
        } else if (character != '\r') {
            current.push_back(character);
        }
    }
    if (!current.empty()) titles.push_back(current);

    if (titles.empty()) {
        state.mode = ScreenMode::Error;
        state.title = "Empty queue";
        state.detail = "The Mac sent a file list with no entries.";
        return false;
    }

    std::sort(titles.begin(), titles.end(), [](const std::string& a, const std::string& b) {
        return lowercased(a) < lowercased(b);
    });

    state.mode = ScreenMode::Queue;
    state.title = "Queue received";
    state.detail = "Installing over USB...";
    state.fileCount = titles.size();
    state.fileIndex = 0;
    renderActiveScreen();
    return true;
}

// Installs one title straight into NCM using the vendored Awoo engine, which
// pulls the NCA / ticket data over the Tinfoil range protocol and registers it.
bool installTitle(const std::string& name, size_t index, size_t count, ScreenState& state) {
    state.mode = ScreenMode::Receiving;
    state.title = "Installing";
    state.detail = state.systemMemory ? "Installing to system memory." : "Installing to SD card.";
    state.fileName = safeDisplayName(name);
    state.fileIndex = index;
    state.fileCount = count;
    state.received = 0;
    state.total = 0;
    state.progress = 0;
    renderActiveScreen();

    const NcmStorageId storageId = state.systemMemory ? NcmStorageId_BuiltInUser : NcmStorageId_SdCard;

    try {
        if (isXciName(name)) {
            auto xci = std::make_shared<tin::install::xci::USBXCI>(name);
            tin::install::xci::XCIInstallTask task(storageId, true, xci);
            task.Prepare();
            task.Begin();
        } else if (isNspName(name)) {
            auto nsp = std::make_shared<tin::install::nsp::USBNSP>(name);
            tin::install::nsp::NSPInstall task(storageId, true, nsp);
            task.Prepare();
            task.Begin();
        } else {
            state.mode = ScreenMode::Error;
            state.title = "Unsupported file";
            state.detail = "This receiver installs .xci and .nsp files only.";
            renderActiveScreen();
            return false;
        }
    } catch (std::exception& e) {
        state.mode = ScreenMode::Error;
        state.title = "Install failed";
        std::string msg = e.what();
        state.detail = msg.substr(0, std::min<size_t>(msg.size(), 90));
        renderActiveScreen();
        return false;
    }

    state.progress = 100;
    renderActiveScreen();
    return true;
}

void waitForExit(ScreenState& state) {
    while (appletMainLoop()) {
        if (userRequestedExit()) {
            break;
        }
        renderActiveScreen();
        svcSleepThread(16'000'000);
    }
}

} // namespace

// ---------------------------------------------------------------------------
// Glue: the vendored engine reports progress via inst::ui::instPage and needs
// inst::util helpers. Defined at namespace scope (external linkage) so the
// engine links against them; they drive the on-screen ScreenState.
// ---------------------------------------------------------------------------

namespace inst::ui::instPage {
    void setInstInfoText(std::string ourText) {
        if (activeState != nullptr) { activeState->detail = ourText; renderActiveScreen(); }
    }
    void setInstBarPerc(double ourPercent) {
        if (activeState != nullptr) { activeState->progress = static_cast<int>(ourPercent); renderActiveScreen(); }
    }
    void setTopInstInfoText(std::string ourText) {
        if (activeState != nullptr) { activeState->title = ourText; renderActiveScreen(); }
    }
    void loadInstallScreen() {
        if (activeState != nullptr) { activeState->mode = ScreenMode::Receiving; renderActiveScreen(); }
    }
    void loadMainMenu() {}
}

namespace inst::util {
    std::string formatUrlString(std::string ourString) { return ourString; }
    void initInstallServices() {
        ncmInitialize();
        nsextInitialize();
        esInitialize();
    }
    void deinitInstallServices() {
        esExit();
        nsextExit();
        ncmExit();
    }
}

int main(int argc, char* argv[]) {
    padConfigureInput(1, HidNpadStyleSet_NpadStandard);

    PadState pad;
    padInitializeDefault(&pad);
    activePad = &pad;

    SwitchLoaderUI ui;
    ui.initialize();

    ScreenState state;
    activeUI = &ui;
    activeState = &state;
    renderActiveScreen();

    UsbCommsInterfaceInfo interfaceInfo{};
    interfaceInfo.bInterfaceClass = 0xFF;
    interfaceInfo.bInterfaceSubClass = 0xFF;
    interfaceInfo.bInterfaceProtocol = 0xFF;

    Result rc = usbCommsInitializeEx(1, &interfaceInfo, kVendorId, kProductId);
    if (R_FAILED(rc)) {
        state.mode = ScreenMode::Error;
        state.title = "USB could not start";
        state.detail = "Close the app and try launching it again from hbmenu.";
        renderActiveScreen();
        waitForExit(state);
        ui.close();
        return 1;
    }

    usbCommsSetErrorHandling(false);

    inst::util::initInstallServices();
    tin::data::NUM_BUFFER_SEGMENTS = 2;

    g_rxBuffer = static_cast<u8*>(std::aligned_alloc(0x1000, kUsbBufferSize));
    if (g_rxBuffer == nullptr) {
        state.mode = ScreenMode::Error;
        state.title = "Memory unavailable";
        state.detail = "Could not allocate the USB receive buffer.";
        renderActiveScreen();
        waitForExit(state);
        usbCommsExit();
        ui.close();
        return 1;
    }

    std::vector<std::string> titles;

    while (appletMainLoop()) {
        if (userRequestedExit()) {
            break;
        }

        if (!readTitleList(titles, state)) {
            if (state.mode == ScreenMode::Error) {
                renderActiveScreen();
                svcSleepThread(1'000'000'000);
                continue;
            }
            break; // user requested exit while waiting
        }

        bool success = true;
        for (size_t index = 0; index < titles.size(); index += 1) {
            if (!installTitle(titles[index], index + 1, titles.size(), state)) {
                success = false;
                break;
            }
        }

        // Always tell the PC we're done so it releases the USB pipe cleanly.
        sendExitCommand();

        state.mode = success ? ScreenMode::Complete : ScreenMode::Error;
        state.title = success ? "Install complete" : "Install failed";
        state.detail = success
            ? (state.systemMemory ? "Installed to system memory." : "Installed to the SD card.")
            : "Check the cable, SD card, and Mac app, then try again.";
        state.progress = success ? 100 : state.progress;
        renderActiveScreen();
        waitForExit(state);
        break;
    }

    inst::util::deinitInstallServices();
    usbCommsExit();
    std::free(g_rxBuffer);
    ui.close();
    return 0;
}
