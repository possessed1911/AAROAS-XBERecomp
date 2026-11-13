// XAPI functions that talk to hardware: controller ports and the hard disk cache partition
#include <chrono>

#include "core/input.h"
#include "xdk/hle.h"
#include "xdk/layout.h"

// configs written before the SDK knew the name
#ifndef SYM_XInputGetCapabilities
#define SYM_XInputGetCapabilities FFFFFC00
#define HAS_XInputGetCapabilities 0
#endif

using namespace kernel;

namespace {

// XPP device type records: CurrentConnected, ChangeConnected, PreviousConnected
constexpr hle::Va kGamepadType = SYM(XPP_GamepadType);
constexpr hle::Va kMemoryUnitType = SYM(XPP_MemoryUnitType);

std::mutex g_ports_lock;
bool g_poller = false;

void UpdatePorts() {
    std::lock_guard<std::mutex> lock(g_ports_lock);
    uint32_t cur = 0;
    for (int p = 0; p < 4; p++)
        if (input::Poll(p).connected) cur |= 1u << p;
    uint32_t old = R32(kGamepadType + XDK_XPP_Current);
    if (cur != old) {
        W32(kGamepadType + XDK_XPP_Changed, R32(kGamepadType + XDK_XPP_Changed) | (cur ^ old));
        W32(kGamepadType + XDK_XPP_Current, cur);
        LOGI("xapi: controller ports now %X", cur);
    }
}

struct Handle {
    uint32_t port;
    uint32_t packet;
    input::Pad last;
};
std::unordered_map<uint32_t, Handle> g_handles;

}  // namespace

HLE_STDCALL(XMountUtilityDrive, 1) {
    CreateSymbolicLink("\\??\\Z:", "\\Device\\Harddisk0\\Partition5");
    return 1;
}

HLE_STDCALL(XInitDevices, 2) {
    XDK_REQUIRE("xapi", XDK_KEY(XPP_Current), XDK_KEY(XPP_Changed), XDK_KEY(XPP_Previous), XDK_DATA(XPP_GamepadType));
    W32(kGamepadType + XDK_XPP_Current, 0);
    W32(kGamepadType + XDK_XPP_Changed, 0);
    W32(kGamepadType + XDK_XPP_Previous, 0);
    if (HAS(XPP_MemoryUnitType)) {  // titles without memory unit support have no record
        W32(kMemoryUnitType + XDK_XPP_Current, 0);
        W32(kMemoryUnitType + XDK_XPP_Changed, 0);
        W32(kMemoryUnitType + XDK_XPP_Previous, 0);
    }
    UpdatePorts();
    if (!g_poller) {
        g_poller = true;
        std::thread([] {
            for (;;) {
                std::this_thread::sleep_for(std::chrono::milliseconds(250));
                UpdatePorts();
            }
        }).detach();
    }
    return 0;
}

HLE_STDCALL(XInputOpen, 4) {
    uint32_t type = a[0], port = a[1];
    if (type != kGamepadType || port > 3) return 0;
    uint32_t h = mem::AllocSystem(16);
    std::lock_guard<std::mutex> lock(g_ports_lock);
    g_handles[h] = {port, 0, {}};
    return h;
}

HLE_STDCALL(XInputClose, 1) {
    std::lock_guard<std::mutex> lock(g_ports_lock);
    g_handles.erase(a[0]);
    mem::FreeSystem(a[0]);
    return 0;
}

namespace dispatch {
uint32_t HostThunk(X86Func* fn);
}

namespace ue2_console {
bool PopCommand(std::string& out);
void AddLog(const std::string& line);
}

static void Ue2OutputSerialize(X86Context& ctx, uint8_t* /*base*/) {
    uint32_t str_va = kernel::R32(ctx.esp + 4);
    if (str_va && mem::IsCommitted(str_va)) {
        std::string msg = kernel::ReadCString(str_va, 1024);
        if (!msg.empty()) ue2_console::AddLog("  " + msg);
    }
    kernel::Return(ctx, 0, 2);
}

HLE_STDCALL(XInputGetState, 2) {
    uint32_t port;
    {
        std::lock_guard<std::mutex> lock(g_ports_lock);
        auto it = g_handles.find(a[0]);
        if (it == g_handles.end()) return 6;  // ERROR_INVALID_HANDLE
        port = it->second.port;
    }
    if (port == 0) {
        std::string cmd;
        while (ue2_console::PopCommand(cmd)) {
            static bool s_zero_page_committed = false;
            if (!s_zero_page_committed) {
                mem::Commit(0, 0x1000);
                s_zero_page_committed = true;
            }
            uint32_t engine = R32(0x0075CF7Cu);
            if (!engine) engine = R32(0x00744CD8u);
            if (!engine || !mem::IsCommitted(engine)) {
                ue2_console::AddLog("[err] GEngine not initialized yet");
                break;
            }
            // Prefer UViewport::Exec (Viewport + 0x30), which routes through UInput, UConsole,
            // UPlayer/Actor/CheatManager UnrealScript exec functions, and chains to GEngine->Exec.
            uint32_t exec_this = 0;
            uint32_t exec_fn = 0;
            uint32_t client = R32(engine + 0x4Cu);
            if (client && mem::IsCommitted(client)) {
                uint32_t vp_data = R32(client + 0x30u);
                uint32_t vp_num = R32(client + 0x34u);
                if (vp_num > 0 && vp_data && mem::IsCommitted(vp_data)) {
                    uint32_t viewport = R32(vp_data);
                    if (viewport && mem::IsCommitted(viewport)) {
                        exec_this = viewport + 0x30u;
                        uint32_t vtbl = R32(exec_this);
                        if (vtbl && mem::IsCommitted(vtbl)) exec_fn = R32(vtbl);
                    }
                }
            }
            if (!exec_this || !exec_fn) {
                exec_this = engine + 0x2Cu;
                uint32_t vtbl = R32(exec_this);
                exec_fn = (vtbl && mem::IsCommitted(vtbl)) ? R32(vtbl) : 0x001A2F20u;
            }
            X86Context saved_ctx = ctx;
            ctx.esp -= 1024;
            uint32_t scratch = ctx.esp;
            uint32_t cmd_va = scratch;
            size_t len = (std::min)(cmd.size(), size_t(511));
            std::memcpy(HostPtr(cmd_va), cmd.data(), len);
            *reinterpret_cast<char*>(HostPtr(cmd_va + len)) = '\0';
            uint32_t ar_va = scratch + 512;
            uint32_t vtbl_va = scratch + 528;
            W32(ar_va, vtbl_va);
            uint32_t serialize_thunk = dispatch::HostThunk(Ue2OutputSerialize);
            W32(vtbl_va + 0, serialize_thunk);
            for (uint32_t i = 1; i < 8; ++i) W32(vtbl_va + i * 4, 0x0011C420u);
            ctx.ecx = exec_this;
            uint32_t ok = CallGuest(ctx, exec_fn, {cmd_va, ar_va});
            ctx = saved_ctx;
            if (!ok) ue2_console::AddLog("[unrecognized]");
        }
    }
    input::Pad p = input::Poll(int(port));
    if (!p.connected) return 1167;  // ERROR_DEVICE_NOT_CONNECTED
    std::lock_guard<std::mutex> lock(g_ports_lock);
    Handle& h = g_handles[a[0]];
    if (std::memcmp(&p, &h.last, sizeof(p))) h.packet++;
    h.last = p;
    uint32_t s = a[1];
    W32(s, h.packet);  // XINPUT_STATE: packet, buttons, 8 analog buttons, thumbs
    W16(s + 4, p.buttons);
    std::memcpy(HostPtr(s + 6), p.analog, 8);
    W16(s + 14, uint16_t(p.lx));
    W16(s + 16, uint16_t(p.ly));
    W16(s + 18, uint16_t(p.rx));
    W16(s + 20, uint16_t(p.ry));
    return 0;
}

// XINPUT_CAPABILITIES: subtype, reserved, the gamepad's buttons, 8 analog buttons and thumbs, then its 2 motors, each
// with every bit set: the controller has them all
HLE_STDCALL(XInputGetCapabilities, 2) {
    constexpr uint32_t kCapsBytes = 25;
    constexpr uint8_t kSubtypeGamepad = 1;  // XINPUT_DEVSUBTYPE_GC_GAMEPAD
    uint32_t port;
    {
        std::lock_guard<std::mutex> lock(g_ports_lock);
        auto it = g_handles.find(a[0]);
        if (it == g_handles.end()) return 6;  // ERROR_INVALID_HANDLE
        port = it->second.port;
    }
    if (!input::Poll(int(port)).connected) return 1167;  // ERROR_DEVICE_NOT_CONNECTED
    uint32_t c = a[1];
    std::memset(HostPtr(c), 0xFF, kCapsBytes);
    G<uint8_t>(c) = kSubtypeGamepad;
    W16(c + 1, 0);
    W16(c + 3, 0x00FF);  // the 8 digital buttons
    return 0;
}

HLE_STDCALL(XInputSetState, 2) {
    uint32_t port;
    {
        std::lock_guard<std::mutex> lock(g_ports_lock);
        auto it = g_handles.find(a[0]);
        if (it == g_handles.end()) return 6;
        port = it->second.port;
    }
    uint32_t fb = a[1];
    // XINPUT_FEEDBACK_HEADER is dwStatus, hEvent and 58 reserved bytes, the rumble follows
    input::Rumble(int(port), R16(fb + 66), R16(fb + 68));
    W32(fb, 0);
    if (uint32_t ev = R32(fb + 4))
        if (ObjectRef o = FromHandle(ev)) SetEvent(*o);
    return 997;  // ERROR_IO_PENDING, already complete
}

// A recompiled image launches through the XAPI, then a process restart into its executable; any other
// (the dashboard, updates) is refused and the title stays in its menu.
X86_EXTERN_FUNC(GUEST_ORIG(XLaunchNewImageA));
X86_FUNC(GUEST(XLaunchNewImageA)) {
    std::string path = ReadCString(R32(ctx.esp + 4));
    if (ImageExe(path)) {
        GUEST_ORIG(XLaunchNewImageA)(ctx, base);
        return;
    }
    LOGW("xapi: launch of %s refused, it is not recompiled", path.c_str());
    Return(ctx, 2, 2);  // ERROR_FILE_NOT_FOUND
}
