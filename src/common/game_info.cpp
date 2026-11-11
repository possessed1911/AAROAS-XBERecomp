#include "app/app.h"
#include "core/input.h"
#include "core/log.h"
#include "gpu/backend.h"
#include <windows.h>
#include <windowsx.h>
#include <filesystem>
#include <stdlib.h>
#include <algorithm>
#include <cmath>
#include <toml++/toml.hpp>

extern "C" {
    __declspec(selectany) char* (*__imp_itoa)(int, char*, int) = _itoa;
    char* itoa(int val, char* buf, int radix) {
        return _itoa(val, buf, radix);
    }
}

// Window and Mouse & Keyboard configuration
static HWND g_hwnd = nullptr;
static bool g_mouse_captured = true;
static float g_mouse_sensitivity = 1.0f;
static bool g_mouse_invert_y = false;

// Mouse look state
static float s_smooth_rx = 0.0f;
static float s_smooth_ry = 0.0f;
static int s_wheel_frames = 0;
static bool s_was_captured = false;

static void OnLoad(const void* table) {
    if (!table) return;
    auto& t = *static_cast<const toml::table*>(table);
    g_mouse_sensitivity = float(t["mouse_sensitivity"].value_or(double(g_mouse_sensitivity)));
    g_mouse_invert_y = t["mouse_invert_y"].value_or(g_mouse_invert_y);
    LOGI("settings: mouse_sensitivity=%.2f, mouse_invert_y=%d", g_mouse_sensitivity, g_mouse_invert_y ? 1 : 0);
}

static void OnSave(void* table) {
    if (!table) return;
    auto& t = *static_cast<toml::table*>(table);
    t.insert_or_assign("mouse_sensitivity", double(g_mouse_sensitivity));
    t.insert_or_assign("mouse_invert_y", g_mouse_invert_y);
}

static void OnInit() {
    namespace fs = std::filesystem;
    std::error_code ec;
    auto dir = app::ExeDir();
    fs::path assets_dir;
    for (int i = 0; i < 6; i++) {
        if (fs::is_directory(dir / "assets", ec)) {
            assets_dir = dir / "assets";
            break;
        }
        if (!dir.has_parent_path() || dir.parent_path() == dir) break;
        dir = dir.parent_path();
    }
    if (!assets_dir.empty()) {
        fs::path hdd_z_system = app::ExeDir() / "hdd" / "Z" / "System";
        fs::create_directories(hdd_z_system, ec);
        fs::path assets_system = assets_dir / "System";
        if (fs::is_directory(assets_system, ec)) {
            for (const auto& entry : fs::directory_iterator(assets_system, ec)) {
                if (entry.path().extension() == ".xmd") {
                    fs::copy_file(entry.path(), hdd_z_system / entry.path().filename(), fs::copy_options::overwrite_existing, ec);
                }
            }
        }
    }
}

static void OnWindow(void* hwnd) {
    g_hwnd = static_cast<HWND>(hwnd);
    LOGI("input: Window registered (%p)", g_hwnd);
    if (g_mouse_captured) {
        while (ShowCursor(FALSE) >= 0);
    }
}

static bool OnMessage(void* hwnd, uint32_t msg, uintptr_t wp, intptr_t lp, intptr_t* result) {
    (void)hwnd; (void)lp; (void)result;
    switch (msg) {
        case WM_ACTIVATE: {
            if (LOWORD(wp) == WA_INACTIVE) {
                ClipCursor(nullptr);
                while (ShowCursor(TRUE) < 0);
                s_was_captured = false;
            } else {
                if (g_mouse_captured) {
                    while (ShowCursor(FALSE) >= 0);
                    s_was_captured = false;
                }
            }
            break;
        }
        case WM_KILLFOCUS: {
            ClipCursor(nullptr);
            while (ShowCursor(TRUE) < 0);
            s_was_captured = false;
            break;
        }
        case WM_SETFOCUS: {
            if (g_mouse_captured) {
                while (ShowCursor(FALSE) >= 0);
                s_was_captured = false;
            }
            break;
        }
        case WM_LBUTTONDOWN: {
            if (!g_mouse_captured && g_hwnd && GetForegroundWindow() == g_hwnd) {
                g_mouse_captured = true;
                s_was_captured = false;
                while (ShowCursor(FALSE) >= 0);
                LOGI("input: Mouse captured on click");
            }
            break;
        }
        case WM_KEYDOWN: {
            if (wp == VK_F1) {
                g_mouse_captured = !g_mouse_captured;
                s_was_captured = false;
                if (g_mouse_captured) {
                    while (ShowCursor(FALSE) >= 0);
                    LOGI("input: Mouse capture ENABLED (F1)");
                } else {
                    ClipCursor(nullptr);
                    while (ShowCursor(TRUE) < 0);
                    LOGI("input: Mouse capture DISABLED (F1)");
                }
                return false;
            }
            break;
        }
        case WM_MOUSEWHEEL: {
            short delta = GET_WHEEL_DELTA_WPARAM(wp);
            if (delta != 0) {
                s_wheel_frames = 4; // Weapon cycle pulse
            }
            break;
        }
    }
    return false;
}

static void HandlePad(int port, input::Pad& pad) {
    if (port != 0) return;

    bool is_foreground = (g_hwnd == nullptr || GetForegroundWindow() == g_hwnd);
    auto is_down = [is_foreground](int vk) {
        return is_foreground && ((GetAsyncKeyState(vk) & 0x8000) != 0);
    };

    bool kb_used = false;

    // 1. Mouse Look (aiming / looking around)
    if (g_mouse_captured && g_hwnd && is_foreground) {
        RECT rc;
        GetClientRect(g_hwnd, &rc);
        POINT center = {(rc.left + rc.right) / 2, (rc.top + rc.bottom) / 2};
        POINT screen_center = center;
        ClientToScreen(g_hwnd, &screen_center);

        POINT cur;
        GetCursorPos(&cur);

        int dx = cur.x - screen_center.x;
        int dy = cur.y - screen_center.y;

        // Clip cursor to window client area so it doesn't wander off
        RECT clip_rc;
        GetClientRect(g_hwnd, &clip_rc);
        MapWindowPoints(g_hwnd, nullptr, reinterpret_cast<POINT*>(&clip_rc), 2);
        ClipCursor(&clip_rc);

        // Re-center cursor
        SetCursorPos(screen_center.x, screen_center.y);

        if (!s_was_captured) {
            // First frame after gaining focus/capture: discard initial delta
            s_was_captured = true;
            dx = 0;
            dy = 0;
            s_smooth_rx = 0.0f;
            s_smooth_ry = 0.0f;
        }

        // Convert mouse deltas (dx, dy) to analog stick deflections (pad.rx, pad.ry)
        constexpr float kDeadzone = 7200.0f;
        constexpr float kMaxStick = 32767.0f;
        float sens = 850.0f * g_mouse_sensitivity;

        float target_rx = 0.0f;
        if (dx != 0) {
            float sign = (dx > 0) ? 1.0f : -1.0f;
            float mag = std::abs((float)dx) * sens;
            target_rx = sign * (kDeadzone + mag);
            target_rx = std::clamp(target_rx, -kMaxStick, kMaxStick);
            kb_used = true;
        }

        float target_ry = 0.0f;
        if (dy != 0) {
            // Screen Y is down positive; stick Y is up positive
            // Mouse up (dy < 0) -> target_ry positive (look UP)
            float sign = (dy < 0) ? 1.0f : -1.0f;
            if (g_mouse_invert_y) sign = -sign;
            float mag = std::abs((float)dy) * sens;
            target_ry = sign * (kDeadzone + mag);
            target_ry = std::clamp(target_ry, -kMaxStick, kMaxStick);
            kb_used = true;
        }

        // Exponential smoothing / fast decay
        if (dx != 0) {
            s_smooth_rx = s_smooth_rx * 0.25f + target_rx * 0.75f;
        } else {
            s_smooth_rx *= 0.2f;
            if (std::abs(s_smooth_rx) < 500.0f) s_smooth_rx = 0.0f;
        }

        if (dy != 0) {
            s_smooth_ry = s_smooth_ry * 0.25f + target_ry * 0.75f;
        } else {
            s_smooth_ry *= 0.2f;
            if (std::abs(s_smooth_ry) < 500.0f) s_smooth_ry = 0.0f;
        }

        if (std::abs(s_smooth_rx) > 100.0f || std::abs(s_smooth_ry) > 100.0f) {
            pad.rx = (int16_t)std::clamp((int)s_smooth_rx, -32768, 32767);
            pad.ry = (int16_t)std::clamp((int)s_smooth_ry, -32768, 32767);
            kb_used = true;
        }

        // Mouse buttons
        if (is_down(VK_LBUTTON)) { pad.analog[7] = 0xFF; kb_used = true; } // Left Click = Fire (RT)
        if (is_down(VK_RBUTTON)) { pad.analog[6] = 0xFF; kb_used = true; } // Right Click = Aim Down Sights (LT)
        if (is_down(VK_MBUTTON)) { pad.buttons |= 0x0080; kb_used = true; } // Middle Click = Melee / Zoom (RS click)
    } else {
        s_was_captured = false;
        s_smooth_rx = 0.0f;
        s_smooth_ry = 0.0f;
    }

    // Mouse wheel pulse (cycle weapon)
    if (s_wheel_frames > 0) {
        s_wheel_frames--;
        pad.analog[3] = 0xFF; // Y button
        kb_used = true;
    }

    // 2. Keyboard Movement (WASD)
    int16_t lx = pad.lx, ly = pad.ly;
    if (is_down('W')) { ly = 32767; kb_used = true; }
    if (is_down('S')) { ly = -32768; kb_used = true; }
    if (is_down('A')) { lx = -32768; kb_used = true; }
    if (is_down('D')) { lx = 32767; kb_used = true; }
    pad.lx = lx;
    pad.ly = ly;

    // Optional keyboard right stick look (IJKL when mouse not moving)
    if (!g_mouse_captured || (pad.rx == 0 && pad.ry == 0)) {
        if (is_down('I')) { pad.ry = 32767; kb_used = true; }
        if (is_down('K')) { pad.ry = -32768; kb_used = true; }
        if (is_down('J')) { pad.rx = -32768; kb_used = true; }
        if (is_down('L')) { pad.rx = 32767; kb_used = true; }
    }

    // 3. Actions / Weapons / Equipment
    // A button: Jump, Vault, Interact, Menu Select
    if (is_down(VK_SPACE) || is_down('E') || is_down(VK_RETURN)) { pad.analog[0] = 0xFF; kb_used = true; }
    // B button: Crouch / Prone, Cancel
    if (is_down('C') || is_down(VK_LCONTROL) || is_down(VK_BACK)) { pad.analog[1] = 0xFF; kb_used = true; }
    // X button: Reload
    if (is_down('R')) { pad.analog[2] = 0xFF; kb_used = true; }
    // Y button: Cycle Weapon / Sidearm
    if (is_down('Q') || is_down('F') || is_down('1') || is_down('2')) { pad.analog[3] = 0xFF; kb_used = true; }
    // Black button: Fire Mode selector
    if (is_down('B') || is_down('4') || is_down('X')) { pad.analog[4] = 0xFF; kb_used = true; }
    // White button: Grenade / Equipment
    if (is_down('G') || is_down('3')) { pad.analog[5] = 0xFF; kb_used = true; }
    // Left Stick Click: Sprint
    if (is_down(VK_LSHIFT)) { pad.buttons |= 0x0040; kb_used = true; }
    // Right Stick Click: Melee / Steady Aim
    if (is_down('V')) { pad.buttons |= 0x0080; kb_used = true; }

    // 4. Menu & System Controls
    // START: Pause / In-Game Menu
    if (is_down(VK_ESCAPE) || is_down(VK_RETURN)) { pad.buttons |= 0x0010; kb_used = true; }
    // BACK: Objectives / Scoreboard
    if (is_down(VK_TAB)) { pad.buttons |= 0x0020; kb_used = true; }

    // 5. Squad Commands / D-Pad
    if (is_down(VK_UP)) { pad.buttons |= 0x0001; kb_used = true; }
    if (is_down(VK_DOWN)) { pad.buttons |= 0x0002; kb_used = true; }
    if (is_down(VK_LEFT) || is_down('Z')) { pad.buttons |= 0x0004; kb_used = true; }
    if (is_down(VK_RIGHT)) { pad.buttons |= 0x0008; kb_used = true; }

    // Check environment variable or auto-press for self-test
    static int s_auto_start = -1;
    if (s_auto_start == -1) {
        s_auto_start = (std::getenv("AA_AUTO_START") != nullptr) ? 1 : 0;
    }
    if (s_auto_start >= 1) {
        static uint32_t auto_frame = 0;
        auto_frame++;
        if (auto_frame >= 250 && auto_frame <= 280) {
            pad.buttons |= 0x0010; // START
            pad.analog[0] = 0xFF;  // A
            static bool s_logged_auto = false;
            if (!s_logged_auto) {
                s_logged_auto = true;
                LOGI("input: Auto-pressing START / A on Press Start screen!");
            }
        } else if (auto_frame >= 500 && auto_frame <= 530) {
            pad.analog[0] = 0xFF;  // A
            static bool s_logged_500 = false;
            if (!s_logged_500) {
                s_logged_500 = true;
                LOGI("input: Auto-pressing A on Main Menu!");
            }
        } else if (auto_frame >= 700 && auto_frame <= 730) {
            pad.analog[0] = 0xFF;  // A
            static bool s_logged_700 = false;
            if (!s_logged_700) {
                s_logged_700 = true;
                LOGI("input: Auto-pressing A on Sub-Menu / Profile!");
            }
        } else if (auto_frame >= 900 && auto_frame <= 930) {
            pad.analog[0] = 0xFF;  // A
            static bool s_logged_900 = false;
            if (!s_logged_900) {
                s_logged_900 = true;
                LOGI("input: Auto-pressing A to confirm / start level!");
            }
        } else if (auto_frame >= 1100 && auto_frame <= 1130) {
            pad.analog[0] = 0xFF;  // A
            static bool s_logged_1100 = false;
            if (!s_logged_1100) {
                s_logged_1100 = true;
                LOGI("input: Auto-pressing A on Mission Select!");
            }
        } else if (auto_frame >= 1400 && auto_frame <= 1430) {
            pad.analog[0] = 0xFF;  // A
            pad.buttons |= 0x0010; // START
            static bool s_logged_1400 = false;
            if (!s_logged_1400) {
                s_logged_1400 = true;
                LOGI("input: Auto-pressing A / START on Mission Select 1!");
            }
        } else if (auto_frame >= 1550 && auto_frame <= 1580) {
            pad.analog[0] = 0xFF;  // A
            pad.buttons |= 0x0010; // START
            static bool s_logged_1550 = false;
            if (!s_logged_1550) {
                s_logged_1550 = true;
                LOGI("input: Auto-pressing A / START on Mission Select 2!");
            }
        } else if (auto_frame >= 1700 && auto_frame <= 1730) {
            pad.analog[0] = 0xFF;  // A
            pad.buttons |= 0x0010; // START
            static bool s_logged_1700 = false;
            if (!s_logged_1700) {
                s_logged_1700 = true;
                LOGI("input: Auto-pressing A / START on Mission Select 3!");
            }
        } else if (auto_frame == 2300) {
            gpu::g_capture = true;
            LOGI("capture: Auto-capturing in-game 3D gameplay frame!");
        }
    }

    if (port == 0 || kb_used) pad.connected = true;
}

// what the runtime asks of the game; strings must be set, hooks may stay null
const app::GameInfo app::kGame = {
    .title = L"America's Army: Rise of a Soldier", // window and splash
    .short_title = L"America's Army",              // message boxes
    .name = L"aa_roas",                            // window classes, crash dumps, handover event
    .log = "aa_roas",                              // log file prefix
    .settings = "settings.toml",                   // settings file beside the exe
    .splash = L"splash",                           // optional splash.png or splash.bmp beside the exe
    .missing = L"Put the game in the assets folder: its disc image (.iso), or default.xbe with its folders beside it.",
    .images = {{"default.xbe", "aa_roas"}},        // each recompiled xbe and its exe, for title launches
    .options = {},                        // game settings kept in the settings file
    .load = OnLoad,                       // reads more from the settings file's toml::table
    .save = OnSave,                       // writes more into it
    .init = OnInit,                       // after the settings load, before the window and boot
    .loaded = nullptr,                    // image in memory, before its entry point runs
    .window = OnWindow,                   // the game window is up
    .message = OnMessage,                 // window messages first; true takes one
    .ui = nullptr,                        // ImGui drawing each frame
    .pad = HandlePad,                     // changes a polled pad
    .rumble = nullptr,                    // changes a rumble before it is set
};
