#include <switch.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/stat.h>
#include <vector>

namespace {

constexpr u16 kVendorId = 0x057E;
constexpr u16 kProductId = 0x3000;
constexpr u16 kProtocolVersion = 1;
constexpr size_t kBufferSize = 0x1000;
constexpr u64 kProgressRenderInterval = 8 * 1024 * 1024;
constexpr const char* kInboxDirectory = "sdmc:/switch/SwitchLoaderReceiver/inbox";
constexpr u32 kScreenWidth = 1280;
constexpr u32 kScreenHeight = 720;

struct FileEntry {
    std::string name;
    u64 size;
};

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
    std::string footer = "Press + to exit";
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
            std::snprintf(
                percentLine,
                sizeof(percentLine),
                "%d%%  %llu / %llu BYTES",
                state.progress,
                static_cast<unsigned long long>(state.received),
                static_cast<unsigned long long>(state.total)
            );
            drawText(percentLine, 516, 526, 2, color(170, 170, 176), 642);
        }

        if (state.mode == ScreenMode::Waiting) {
            drawText("WAITING FOR THE MAC APP", 516, 328, 3, color(120, 205, 228), 642);
            drawText("CHOOSE FILES, THEN PRESS SEND TO SWITCHLOADER RECEIVER.", 516, 376, 2, color(178, 178, 184), 642);
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
    return (padGetButtonsDown(activePad) & HidNpadButton_Plus) != 0;
}

void renderActiveScreen() {
    if (activeUI != nullptr && activeState != nullptr) {
        activeUI->render(*activeState);
    }
}

bool readExact(void* destination, size_t size) {
    auto* cursor = static_cast<u8*>(destination);
    size_t received = 0;

    while (received < size && appletMainLoop()) {
        if (userRequestedExit()) {
            return false;
        }

        const size_t count = usbCommsRead(cursor + received, size - received);
        if (count == 0) {
            renderActiveScreen();
            svcSleepThread(16'000'000);
            continue;
        }
        received += count;
    }

    return received == size;
}

bool readBodyChunk(void* destination, size_t size, size_t& transferred) {
    transferred = 0;

    while (appletMainLoop()) {
        if (userRequestedExit()) {
            return false;
        }

        u32 urbId = 0;
        Result rc = usbCommsReadAsync(destination, size, &urbId, 0);
        if (R_FAILED(rc)) {
            renderActiveScreen();
            svcSleepThread(1'000'000);
            continue;
        }

        Event* completionEvent = usbCommsGetReadCompletionEvent(0);
        while (appletMainLoop()) {
            if (userRequestedExit()) {
                return false;
            }

            rc = eventWait(completionEvent, 16'000'000);
            if (R_SUCCEEDED(rc)) {
                eventClear(completionEvent);
                break;
            }

            renderActiveScreen();
        }

        u32 transferredSize = 0;
        rc = usbCommsGetReadResult(urbId, &transferredSize, 0);
        if (R_FAILED(rc)) {
            renderActiveScreen();
            svcSleepThread(1'000'000);
            continue;
        }

        if (transferredSize == 0) {
            renderActiveScreen();
            svcSleepThread(1'000'000);
            continue;
        }

        transferred = transferredSize;
        return true;
    }

    return false;
}

template <typename T>
bool readLittleEndian(T& value) {
    std::array<u8, sizeof(T)> bytes{};
    if (!readExact(bytes.data(), bytes.size())) {
        return false;
    }

    value = 0;
    for (size_t index = 0; index < bytes.size(); index += 1) {
        value |= static_cast<T>(bytes[index]) << static_cast<T>(index * 8);
    }
    return true;
}

std::string lowercased(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

bool isAllowedInstallRoot(const std::string& component) {
    const std::string root = lowercased(component);
    return root == "atmosphere" || root == "bootloader" || root == "config" || root == "switch" || root == "themes";
}

std::string safePathComponent(const std::string& name) {
    std::string output;
    output.reserve(name.size());

    for (const char character : name) {
        switch (character) {
            case '/':
            case ':':
            case '?':
            case '#':
            case '[':
            case ']':
            case '@':
            case '!':
            case '$':
            case '&':
            case '\'':
            case '(':
            case ')':
            case '*':
            case '+':
            case ',':
            case ';':
            case '=':
                output.push_back('_');
                break;
            default:
                output.push_back(character);
                break;
        }
    }

    if (output.empty() || output == "." || output == "..") {
        return "_";
    }

    return output;
}

std::string safeRelativePath(const std::string& path) {
    std::vector<std::string> components;
    std::string current;

    for (const char character : path) {
        if (character == '/' || character == '\\') {
            if (!current.empty()) {
                components.push_back(safePathComponent(current));
                current.clear();
            }
        } else {
            current.push_back(character);
        }
    }

    if (!current.empty()) {
        components.push_back(safePathComponent(current));
    }

    components.erase(
        std::remove_if(components.begin(), components.end(), [](const std::string& component) {
            return component.empty() || component == ".";
        }),
        components.end()
    );

    if (components.empty()) {
        components = {"switch", "SwitchLoaderReceiver", "received.bin"};
    } else if (!isAllowedInstallRoot(components.front())) {
        components.insert(components.begin(), {"switch", "SwitchLoaderReceiver", "Homebrew Assets"});
    }

    std::string output;
    for (const std::string& component : components) {
        if (!output.empty()) {
            output.push_back('/');
        }
        output.append(component);
    }
    return output;
}

bool ensureParentDirectories(const std::string& path) {
    size_t position = path.find('/', std::strlen("sdmc:/"));
    while (position != std::string::npos) {
        const std::string directory = path.substr(0, position);
        if (mkdir(directory.c_str(), 0777) != 0 && errno != EEXIST) {
            return false;
        }
        position = path.find('/', position + 1);
    }
    return true;
}

bool readManifest(std::vector<FileEntry>& files, ScreenState& state) {
    state.mode = ScreenMode::Waiting;
    state.title = "Ready to receive";
    state.detail = "Choose files in SwitchLoader on your Mac, then send to this receiver.";
    state.fileName.clear();
    state.progress = 0;
    renderActiveScreen();

    char magic[4]{};
    if (!readExact(magic, sizeof(magic)) || std::memcmp(magic, "SLR0", 4) != 0) {
        return false;
    }

    u16 version = 0;
    u16 fileCount = 0;
    if (!readLittleEndian(version) || !readLittleEndian(fileCount)) {
        state.mode = ScreenMode::Error;
        state.title = "Manifest failed";
        state.detail = "Could not read the file list from the Mac.";
        return false;
    }

    if (version != kProtocolVersion) {
        state.mode = ScreenMode::Error;
        state.title = "Protocol mismatch";
        state.detail = "Update SwitchLoader on both the Mac and the Switch.";
        return false;
    }

    files.clear();
    files.reserve(fileCount);

    for (u16 index = 0; index < fileCount; index += 1) {
        u16 nameLength = 0;
        if (!readLittleEndian(nameLength) || nameLength == 0) {
            state.mode = ScreenMode::Error;
            state.title = "Bad file name";
            state.detail = "The Mac sent an invalid queue entry.";
            return false;
        }

        std::string name(nameLength, '\0');
        if (!readExact(name.data(), nameLength)) {
            state.mode = ScreenMode::Error;
            state.title = "File list failed";
            state.detail = "Could not read a file name from the Mac.";
            return false;
        }

        u64 size = 0;
        if (!readLittleEndian(size)) {
            state.mode = ScreenMode::Error;
            state.title = "File list failed";
            state.detail = "Could not read a file size from the Mac.";
            return false;
        }

        files.push_back({safeRelativePath(name), size});
    }

    state.mode = ScreenMode::Queue;
    state.title = "Queue received";
    state.detail = "Installing Homebrew files into their SD card folders.";
    state.fileCount = files.size();
    state.fileIndex = 0;
    renderActiveScreen();
    return true;
}

bool ensureInboxDirectory() {
    mkdir("sdmc:/switch", 0777);
    mkdir("sdmc:/switch/SwitchLoaderReceiver", 0777);
    return mkdir(kInboxDirectory, 0777) == 0 || errno == EEXIST;
}

bool receiveFile(const FileEntry& file, size_t index, size_t count, u8* buffer, ScreenState& state) {
    char fileMagic[4]{};
    if (!readExact(fileMagic, sizeof(fileMagic)) || std::memcmp(fileMagic, "FILE", 4) != 0) {
        state.mode = ScreenMode::Error;
        state.title = "Transfer failed";
        state.detail = "The next file marker was missing.";
        state.fileName = file.name;
        renderActiveScreen();
        return false;
    }

    const std::string path = std::string("sdmc:/") + file.name;
    if (!ensureParentDirectories(path)) {
        state.mode = ScreenMode::Error;
        state.title = "Folder create failed";
        state.detail = "Could not create the Homebrew folder on the SD card.";
        state.fileName = file.name;
        renderActiveScreen();
        return false;
    }

    FILE* output = std::fopen(path.c_str(), "wb");
    if (output == nullptr) {
        state.mode = ScreenMode::Error;
        state.title = "SD write failed";
        state.detail = "Could not open the inbox file for writing.";
        state.fileName = file.name;
        renderActiveScreen();
        return false;
    }

    state.mode = ScreenMode::Receiving;
    state.title = "Installing Homebrew";
    state.detail = "Writing generated Homebrew files to the SD card.";
    state.fileName = file.name;
    state.fileIndex = index;
    state.fileCount = count;
    state.received = 0;
    state.total = file.size;
    state.progress = 0;
    renderActiveScreen();

    u64 received = 0;
    u64 lastRendered = 0;
    while (received < file.size && appletMainLoop()) {
        const size_t nextSize = static_cast<size_t>(std::min<u64>(kBufferSize, file.size - received));
        size_t transferred = 0;
        if (!readBodyChunk(buffer, nextSize, transferred)) {
            std::fclose(output);
            state.mode = ScreenMode::Error;
            state.title = "USB read failed";
            state.detail = "The cable transfer stopped before the file was complete.";
            renderActiveScreen();
            return false;
        }

        const size_t written = std::fwrite(buffer, 1, transferred, output);
        if (written != transferred) {
            std::fclose(output);
            state.mode = ScreenMode::Error;
            state.title = "SD write failed";
            state.detail = "The SD card could not save the incoming file.";
            renderActiveScreen();
            return false;
        }

        received += transferred;
        state.received = received;
        state.total = file.size;
        state.progress = file.size == 0 ? 100 : static_cast<int>((received * 100) / file.size);
        if (received == file.size || received - lastRendered >= kProgressRenderInterval) {
            renderActiveScreen();
            lastRendered = received;
        }
    }

    std::fclose(output);
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
    if (!ensureInboxDirectory()) {
        state.mode = ScreenMode::Error;
        state.title = "Inbox unavailable";
        state.detail = "Could not create sdmc:/switch/SwitchLoaderReceiver/inbox.";
        renderActiveScreen();
        waitForExit(state);
        usbCommsExit();
        ui.close();
        return 1;
    }

    auto* buffer = static_cast<u8*>(std::aligned_alloc(0x1000, kBufferSize));
    if (buffer == nullptr) {
        state.mode = ScreenMode::Error;
        state.title = "Memory unavailable";
        state.detail = "Could not allocate the USB receive buffer.";
        renderActiveScreen();
        waitForExit(state);
        usbCommsExit();
        ui.close();
        return 1;
    }

    std::vector<FileEntry> files;

    while (appletMainLoop()) {
        if (userRequestedExit()) {
            break;
        }

        if (!readManifest(files, state)) {
            if (state.mode == ScreenMode::Error) {
                renderActiveScreen();
                svcSleepThread(1'000'000'000);
            }
            continue;
        }

        bool success = true;
        for (size_t index = 0; index < files.size(); index += 1) {
            if (!receiveFile(files[index], index + 1, files.size(), buffer, state)) {
                success = false;
                break;
            }
        }

        state.mode = success ? ScreenMode::Complete : ScreenMode::Error;
        state.title = success ? "Transfer complete" : "Transfer failed";
        state.detail = success ? "Files are saved in the SwitchLoader inbox on your SD card." : "Check the cable, SD card, and Mac app, then try again.";
        state.progress = success ? 100 : state.progress;
        renderActiveScreen();
        waitForExit(state);
        break;
    }

    usbCommsExit();
    std::free(buffer);
    ui.close();
    return 0;
}
