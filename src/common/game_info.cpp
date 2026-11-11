#include "app/app.h"
#include "core/input.h"
#include "core/log.h"
#include "gpu/backend.h"
#include <windows.h>
#include <windowsx.h>
#include <filesystem>
#include <stdlib.h>
#include <algorithm>
#include <atomic>
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
static std::atomic<float> g_mouse_sensitivity{1.0f};
static std::atomic<bool> g_mouse_invert_y{false};

// Mouse look & capture state
// SRWLOCK avoids CRT atexit destructor hazards when xapi's background port poller calls HandlePad.
static SRWLOCK g_capture_lock = SRWLOCK_INIT;
static bool s_window_active = false;
static bool s_in_size_move = false;
static bool s_in_menu_loop = false;
static bool s_nc_mouse_down = false;
static bool s_wait_client_entry = false;
static bool s_cursor_clipped = false;
static float s_smooth_rx = 0.0f;
static float s_smooth_ry = 0.0f;
static std::atomic<int> s_wheel_frames{0};
static bool s_was_captured = false;

struct SrwExclusiveGuard {
    SRWLOCK& lock;
    explicit SrwExclusiveGuard(SRWLOCK& l) : lock(l) { AcquireSRWLockExclusive(&lock); }
    ~SrwExclusiveGuard() { ReleaseSRWLockExclusive(&lock); }
    SrwExclusiveGuard(const SrwExclusiveGuard&) = delete;
    SrwExclusiveGuard& operator=(const SrwExclusiveGuard&) = delete;
};

static bool IsAltDown() {
    return (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
}

static bool IsAnyMouseButtonDown() {
    return ((GetAsyncKeyState(VK_LBUTTON) | GetAsyncKeyState(VK_RBUTTON) | GetAsyncKeyState(VK_MBUTTON)) & 0x8000) != 0;
}

static bool GetScreenClientRect(HWND hwnd, RECT& out_rc) {
    if (!hwnd || !GetClientRect(hwnd, &out_rc)) return false;
    if (out_rc.right <= out_rc.left || out_rc.bottom <= out_rc.top) return false;
    MapWindowPoints(hwnd, nullptr, reinterpret_cast<POINT*>(&out_rc), 2);
    return true;
}

static void ResetMouseLookStateLocked() {
    s_was_captured = false;
    s_smooth_rx = 0.0f;
    s_smooth_ry = 0.0f;
}

static void ReleaseCursorClipLocked() {
    if (s_cursor_clipped) {
        ClipCursor(nullptr);
        s_cursor_clipped = false;
    }
}

static bool CanCaptureLocked(bool check_foreground, bool alt_held) {
    if (!g_mouse_captured || !g_hwnd || !s_window_active) return false;
    if (s_in_size_move || s_in_menu_loop || s_nc_mouse_down || s_wait_client_entry || alt_held) return false;
    if (IsIconic(g_hwnd)) return false;
    if (check_foreground && GetForegroundWindow() != g_hwnd) return false;
    return true;
}

static void RefreshUiCursor(HWND hwnd, bool capture_ready) {
    if (!hwnd) return;
    if (GetForegroundWindow() == hwnd && !IsIconic(hwnd)) {
        SetCursor(capture_ready ? nullptr : LoadCursorW(nullptr, IDC_ARROW));
    }
}

static void ReleaseCaptureUiLocked(HWND hwnd) {
    ResetMouseLookStateLocked();
    ClipCursor(nullptr);
    s_cursor_clipped = false;
    RefreshUiCursor(hwnd, false);
}

static float MouseDeltaToStick(int delta, float sens, float axis_scale, float sign) {
    if (delta == 0) return 0.0f;
    constexpr float kDeadzone = 7200.0f;
    constexpr float kMaxStick = 32767.0f;
    const float mag = std::abs(static_cast<float>(delta)) * sens * axis_scale;
    return std::clamp(sign * (kDeadzone + mag), -kMaxStick, kMaxStick);
}

static void SmoothStickAxis(int delta, float target, float& smoothed) {
    if (delta != 0) {
        // Jump immediately from standstill so 1px micro-aim clears the engine deadzone on frame 1.
        smoothed = (smoothed == 0.0f) ? target : (smoothed * 0.25f + target * 0.75f);
        return;
    }
    smoothed *= 0.2f;
    if (std::abs(smoothed) < 500.0f) smoothed = 0.0f;
}

static void OnLoad(const void* table) {
    if (!table) return;
    auto& t = *static_cast<const toml::table*>(table);
    const float sens = (std::max)(0.01f, float(t["mouse_sensitivity"].value_or(double(g_mouse_sensitivity.load(std::memory_order_relaxed)))));
    const bool invert = t["mouse_invert_y"].value_or(g_mouse_invert_y.load(std::memory_order_relaxed));
    g_mouse_sensitivity.store(sens, std::memory_order_relaxed);
    g_mouse_invert_y.store(invert, std::memory_order_relaxed);
    LOGI("settings: mouse_sensitivity=%.2f, mouse_invert_y=%d", sens, invert ? 1 : 0);
}

static void OnSave(void* table) {
    if (!table) return;
    auto& t = *static_cast<toml::table*>(table);
    t.insert_or_assign("mouse_sensitivity", double(g_mouse_sensitivity.load(std::memory_order_relaxed)));
    t.insert_or_assign("mouse_invert_y", g_mouse_invert_y.load(std::memory_order_relaxed));
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
    SrwExclusiveGuard lock(g_capture_lock);
    g_hwnd = static_cast<HWND>(hwnd);
    s_window_active = (g_hwnd != nullptr && GetForegroundWindow() == g_hwnd && !IsIconic(g_hwnd));
    s_in_size_move = false;
    s_in_menu_loop = false;
    s_nc_mouse_down = false;
    s_wait_client_entry = false;
    ResetMouseLookStateLocked();
    LOGI("input: Window registered (%p)", g_hwnd);
    RefreshUiCursor(g_hwnd, CanCaptureLocked(false, IsAltDown()));
}

static bool OnMessage(void* hwnd, uint32_t msg, uintptr_t wp, intptr_t lp, intptr_t* result) {
    (void)hwnd;
    switch (msg) {
        case WM_SETCURSOR: {
            if (LOWORD(lp) == HTCLIENT) {
                SrwExclusiveGuard lock(g_capture_lock);
                if (CanCaptureLocked(true, IsAltDown())) {
                    SetCursor(nullptr);
                    if (result) *result = TRUE;
                    return true;
                }
            }
            return false;
        }
        case WM_MOUSEACTIVATE: {
            SrwExclusiveGuard lock(g_capture_lock);
            if (LOWORD(lp) != HTCLIENT) {
                // Keep cursor free when activating via title bar, borders, or window buttons.
                s_nc_mouse_down = true;
                s_wait_client_entry = true;
                ReleaseCaptureUiLocked(g_hwnd);
            } else {
                s_nc_mouse_down = false;
                s_wait_client_entry = false;
            }
            break;
        }
        case WM_ACTIVATE: {
            SrwExclusiveGuard lock(g_capture_lock);
            const bool active = (LOWORD(wp) != WA_INACTIVE) && (HIWORD(wp) == 0);
            s_window_active = active;
            if (!active) {
                s_in_size_move = false;
                s_in_menu_loop = false;
                s_nc_mouse_down = false;
                s_wait_client_entry = false;
                ReleaseCaptureUiLocked(g_hwnd);
            } else {
                // Keyboard/taskbar activation (WA_ACTIVE) resumes capture immediately; click activation
                // preserves s_wait_client_entry set by WM_MOUSEACTIVATE on non-client areas.
                if (LOWORD(wp) == WA_ACTIVE) {
                    s_nc_mouse_down = false;
                    s_wait_client_entry = false;
                }
                ResetMouseLookStateLocked();
                RefreshUiCursor(g_hwnd, CanCaptureLocked(false, IsAltDown()));
            }
            break;
        }
        case WM_ACTIVATEAPP: {
            if (!wp) {
                SrwExclusiveGuard lock(g_capture_lock);
                s_window_active = false;
                s_in_size_move = false;
                s_in_menu_loop = false;
                s_nc_mouse_down = false;
                s_wait_client_entry = false;
                ReleaseCaptureUiLocked(g_hwnd);
            }
            break;
        }
        case WM_KILLFOCUS: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_window_active = false;
            s_nc_mouse_down = false;
            s_wait_client_entry = false;
            ReleaseCaptureUiLocked(g_hwnd);
            break;
        }
        case WM_SETFOCUS: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_window_active = (g_hwnd != nullptr && !IsIconic(g_hwnd));
            ResetMouseLookStateLocked();
            RefreshUiCursor(g_hwnd, CanCaptureLocked(false, IsAltDown()));
            break;
        }
        case WM_NCLBUTTONDOWN:
        case WM_NCRBUTTONDOWN:
        case WM_NCMBUTTONDOWN: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_nc_mouse_down = true;
            s_wait_client_entry = true;
            ReleaseCaptureUiLocked(g_hwnd);
            break;
        }
        case WM_NCLBUTTONUP:
        case WM_NCRBUTTONUP:
        case WM_NCMBUTTONUP:
        case WM_CAPTURECHANGED: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_nc_mouse_down = false;
            ResetMouseLookStateLocked();
            RefreshUiCursor(g_hwnd, CanCaptureLocked(false, IsAltDown()));
            break;
        }
        case WM_ENTERSIZEMOVE: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_in_size_move = true;
            ReleaseCaptureUiLocked(g_hwnd);
            break;
        }
        case WM_EXITSIZEMOVE: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_in_size_move = false;
            s_nc_mouse_down = false;
            RECT clip_rc{};
            POINT pt{};
            const bool in_client = GetScreenClientRect(g_hwnd, clip_rc) && GetCursorPos(&pt) && PtInRect(&clip_rc, pt) != FALSE;
            // After dragging/resizing from the titlebar/border, wait until cursor returns into the client area.
            s_wait_client_entry = !in_client;
            ResetMouseLookStateLocked();
            RefreshUiCursor(g_hwnd, CanCaptureLocked(false, IsAltDown()));
            break;
        }
        case WM_ENTERMENULOOP: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_in_menu_loop = true;
            ReleaseCaptureUiLocked(g_hwnd);
            break;
        }
        case WM_EXITMENULOOP: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_in_menu_loop = false;
            ResetMouseLookStateLocked();
            RefreshUiCursor(g_hwnd, CanCaptureLocked(false, IsAltDown()));
            break;
        }
        case WM_SYSKEYDOWN:
        case WM_SYSKEYUP:
        case WM_KEYUP: {
            if (wp == VK_MENU) {
                SrwExclusiveGuard lock(g_capture_lock);
                const bool alt_down = (msg == WM_SYSKEYDOWN);
                if (alt_down) {
                    ReleaseCaptureUiLocked(g_hwnd);
                } else {
                    RECT clip_rc{};
                    POINT pt{};
                    const bool in_client = GetScreenClientRect(g_hwnd, clip_rc) && GetCursorPos(&pt) && PtInRect(&clip_rc, pt) != FALSE;
                    if (!in_client) s_wait_client_entry = true;
                    ResetMouseLookStateLocked();
                    RefreshUiCursor(g_hwnd, CanCaptureLocked(false, false));
                }
            }
            break;
        }
        case WM_LBUTTONDOWN:
        case WM_RBUTTONDOWN:
        case WM_MBUTTONDOWN: {
            SrwExclusiveGuard lock(g_capture_lock);
            s_nc_mouse_down = false;
            s_wait_client_entry = false;
            if (g_hwnd && GetForegroundWindow() == g_hwnd && !IsIconic(g_hwnd)) {
                s_window_active = true;
                if (!g_mouse_captured) {
                    g_mouse_captured = true;
                    LOGI("input: Mouse captured on click");
                }
                ResetMouseLookStateLocked();
                RefreshUiCursor(g_hwnd, CanCaptureLocked(false, IsAltDown()));
            }
            break;
        }
        case WM_KEYDOWN: {
            if (wp == VK_F1) {
                SrwExclusiveGuard lock(g_capture_lock);
                g_mouse_captured = !g_mouse_captured;
                s_nc_mouse_down = false;
                s_wait_client_entry = false;
                ResetMouseLookStateLocked();
                const bool can = CanCaptureLocked(false, IsAltDown());
                if (!can) ReleaseCaptureUiLocked(g_hwnd);
                else RefreshUiCursor(g_hwnd, true);
                LOGI("input: Mouse capture %s (F1)", g_mouse_captured ? "ENABLED" : "DISABLED");
                return false;
            }
            break;
        }
        case WM_MOUSEWHEEL: {
            short delta = GET_WHEEL_DELTA_WPARAM(wp);
            if (delta != 0) {
                s_wheel_frames.store(4, std::memory_order_relaxed); // Weapon cycle pulse
            }
            break;
        }
    }
    return false;
}

static void HandlePad(int port, input::Pad& pad) {
    if (port != 0) return;

    const bool alt_held = IsAltDown();
    const bool any_mouse_btn = IsAnyMouseButtonDown();
    bool kb_used = false;
    bool is_foreground = false;
    bool mouse_captured_snapshot = false;
    HWND notify_cursor_hwnd = nullptr;

    // 1. Mouse Look (aiming / looking around)
    {
        SrwExclusiveGuard lock(g_capture_lock);
        if (s_nc_mouse_down && !any_mouse_btn && !s_in_size_move) {
            s_nc_mouse_down = false;
        }

        is_foreground = (g_hwnd == nullptr || (GetForegroundWindow() == g_hwnd && !IsIconic(g_hwnd)));
        mouse_captured_snapshot = g_mouse_captured;

        RECT clip_rc{};
        POINT cur{};
        const bool has_client_rect = GetScreenClientRect(g_hwnd, clip_rc);
        const bool has_cursor = has_client_rect && GetCursorPos(&cur);
        if (s_wait_client_entry && has_cursor && PtInRect(&clip_rc, cur) != FALSE) {
            s_wait_client_entry = false;
        }

        if (has_cursor && CanCaptureLocked(true, alt_held)) {
            const POINT screen_center = {(clip_rc.left + clip_rc.right) / 2,
                                         (clip_rc.top + clip_rc.bottom) / 2};

            int dx = cur.x - screen_center.x;
            int dy = cur.y - screen_center.y;

            const bool first_capture = !s_was_captured;
            // Clip cursor to client area while active and reset it to center for relative deltas.
            ClipCursor(&clip_rc);
            s_cursor_clipped = true;
            SetCursorPos(screen_center.x, screen_center.y);

            if (first_capture) {
                // Discard the first delta after regaining focus/capture so the camera never snaps.
                s_was_captured = true;
                dx = 0;
                dy = 0;
                s_smooth_rx = 0.0f;
                s_smooth_ry = 0.0f;
                // Trigger UI thread WM_SETCURSOR so Alt-Tab return hides arrow immediately even if stationary.
                notify_cursor_hwnd = g_hwnd;
            }

            // Compensate for UE2's slower vertical look multiplier (xboxuser.ini 150 yaw vs 100 pitch).
            constexpr float kVerticalAimScale = 1.5f;
            const float sens = 850.0f * g_mouse_sensitivity.load(std::memory_order_relaxed);
            const bool invert_y = g_mouse_invert_y.load(std::memory_order_relaxed);

            const float target_rx = MouseDeltaToStick(dx, sens, 1.0f, (dx > 0) ? 1.0f : -1.0f);
            float y_sign = (dy < 0) ? 1.0f : -1.0f;
            if (invert_y) y_sign = -y_sign;
            const float target_ry = MouseDeltaToStick(dy, sens, kVerticalAimScale, y_sign);

            SmoothStickAxis(dx, target_rx, s_smooth_rx);
            SmoothStickAxis(dy, target_ry, s_smooth_ry);

            if (dx != 0 || dy != 0 ||
                std::abs(s_smooth_rx) > 100.0f || std::abs(s_smooth_ry) > 100.0f) {
                pad.rx = static_cast<int16_t>(std::clamp(static_cast<int>(s_smooth_rx), -32768, 32767));
                pad.ry = static_cast<int16_t>(std::clamp(static_cast<int>(s_smooth_ry), -32768, 32767));
                kb_used = true;
            }

            // Mouse buttons (only while actively captured inside client area)
            if (is_foreground && !alt_held) {
                if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0) { pad.analog[7] = 0xFF; kb_used = true; } // Fire (RT)
                if ((GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0) { pad.analog[6] = 0xFF; kb_used = true; } // ADS (LT)
                if ((GetAsyncKeyState(VK_MBUTTON) & 0x8000) != 0) { pad.buttons |= 0x0080; kb_used = true; } // Melee / Zoom (RS)
            }
        } else {
            const bool was_clipped = s_cursor_clipped;
            ResetMouseLookStateLocked();
            ReleaseCursorClipLocked();
            if (was_clipped && g_hwnd && is_foreground) {
                notify_cursor_hwnd = g_hwnd;
            }
        }
    }

    if (notify_cursor_hwnd) {
        PostMessageW(notify_cursor_hwnd, WM_SETCURSOR,
                     reinterpret_cast<WPARAM>(notify_cursor_hwnd), MAKELPARAM(HTCLIENT, 0));
    }

    auto is_down = [is_foreground, alt_held](int vk) {
        return is_foreground && !alt_held && ((GetAsyncKeyState(vk) & 0x8000) != 0);
    };

    // Mouse wheel pulse (cycle weapon)
    int wheel = s_wheel_frames.load(std::memory_order_relaxed);
    while (wheel > 0 && !s_wheel_frames.compare_exchange_weak(wheel, wheel - 1, std::memory_order_relaxed)) {}
    if (wheel > 0) {
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
    if (!mouse_captured_snapshot || (pad.rx == 0 && pad.ry == 0)) {
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
