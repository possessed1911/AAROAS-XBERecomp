#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <cstring>
#include <algorithm>
#include "cpu/x86_context.h"
#include "cpu/x86_ops.h"
#include "core/log.h"
#include "core/input.h"
#include "gpu/texture.h"
#include "xdk/d3d8.h"

// sub_002F4540: MoviePlayer::Update()
// Handles playback of Xbox Media Video (.xmv) streams.
// Allows skipping intro/cutscene videos if user presses Space, Enter, Escape, or controller buttons.
bool FixMovieUpdate(X86Context& ctx, uint8_t* base) {
    (void)base;

    // Track thread changes: each movie is played by a dedicated worker thread
    DWORD tid = GetCurrentThreadId();
    static DWORD s_last_tid = 0;
    static uint32_t s_movie_frames = 0;

    if (tid != s_last_tid) {
        s_last_tid = tid;
        s_movie_frames = 0;
    }
    s_movie_frames++;

    // Grace period of 15 frames (~0.25s) before accepting skip to avoid accidental double-skips
    bool skip = false;
    if (s_movie_frames >= 15) {
        auto is_down = [](int vk) {
            return (GetAsyncKeyState(vk) & 0x8000) != 0;
        };
        bool kb_skip = is_down(VK_SPACE) || is_down(VK_RETURN) || is_down(VK_ESCAPE) || is_down('E');

        // Check gamepad buttons (A, B, X, Y, Start)
        bool pad_skip = false;
        uint16_t held = input::HeldOnAnyController();
        if (held & 0xF000) {
            pad_skip = true;
        } else {
            input::Pad p0 = input::Poll(0);
            if ((p0.buttons & 0x0010) || (p0.analog[0] > 100)) { // Start or A button
                pad_skip = true;
            }
        }

        skip = kb_skip || pad_skip;
    }

    if (skip) {
        ctx.eax = 0; // movie ended
        return true;
    }

    // Let the real sub_002F4540 run to decode video frames!
    return false;
}

// D3DDevice_IsOverlayActive (0x003C3790)
// Returning 1 indicates overlay is active so sub_002F4540 passes the overlay surface to XmvGetNextFrame!
bool FixOverlayActive(X86Context& ctx, uint8_t* base) {
    (void)base;
    ctx.eax = 1;
    return true;
}

// D3DDevice_UpdateOverlay (0x003C37B0)
// Takes 5 parameters (0x14 bytes on stack), returns D3D_OK (0).
// Exhibits decoded YUY2 video frame by converting to 32-bit BGRA and copying to the backbuffer.
bool FixOverlayUpdate(X86Context& ctx, uint8_t* base) {
    uint32_t pOverlay = X86_MEM32(ctx.esp + 4);
    uint32_t pDestRect = X86_MEM32(ctx.esp + 8);
    uint32_t pSrcRect = X86_MEM32(ctx.esp + 12);

    if (pOverlay) {
        uint32_t dev = X86_MEM32(0x003CE168);
        uint32_t rt = dev ? X86_MEM32(dev + 0x1A04) : 0; // CDevice_RenderTarget

        if (rt) {
            uint32_t src_data = X86_MEM32(pOverlay + 4);
            uint32_t src_size = X86_MEM32(pOverlay + 16);
            uint32_t src_w = (src_size & 0xFFF) + 1;
            uint32_t src_h = ((src_size >> 12) & 0xFFF) + 1;
            uint32_t src_pitch = (((src_size >> 24) & 0xFF) + 1) * 64;

            uint32_t dst_data = X86_MEM32(rt + 4);
            uint32_t dst_size = X86_MEM32(rt + 16);
            uint32_t dst_w = (dst_size & 0xFFF) + 1;
            uint32_t dst_h = ((dst_size >> 12) & 0xFFF) + 1;
            uint32_t dst_pitch = (((dst_size >> 24) & 0xFF) + 1) * 64;

            if (!src_data || !dst_data) {
                ctx.eax = 0;
                return true;
            }

            uint32_t src_va = (src_data < 0x04000000) ? (0x80000000 | src_data) : src_data;
            uint32_t dst_va = (dst_data < 0x04000000) ? (0x80000000 | dst_data) : dst_data;

            const uint8_t* src = base + src_va;
            uint8_t* dst = base + dst_va;

            // Destination rect clamping
            int dst_x0 = 0, dst_y0 = 0, dst_x1 = (int)dst_w, dst_y1 = (int)dst_h;
            if (pDestRect) {
                int32_t left = (int32_t)X86_MEM32(pDestRect);
                int32_t top = (int32_t)X86_MEM32(pDestRect + 4);
                int32_t right = (int32_t)X86_MEM32(pDestRect + 8);
                int32_t bottom = (int32_t)X86_MEM32(pDestRect + 12);
                if (right > left && bottom > top) {
                    dst_x0 = left < 0 ? 0 : (left > (int)dst_w ? (int)dst_w : left);
                    dst_y0 = top < 0 ? 0 : (top > (int)dst_h ? (int)dst_h : top);
                    dst_x1 = right < 0 ? 0 : (right > (int)dst_w ? (int)dst_w : right);
                    dst_y1 = bottom < 0 ? 0 : (bottom > (int)dst_h ? (int)dst_h : bottom);
                }
            }

            int target_w = dst_x1 - dst_x0;
            int target_h = dst_y1 - dst_y0;

            // Clear black letterbox/pillarbox margins if dest rect does not fill the entire buffer
            if (dst_y0 > 0) {
                std::memset(dst, 0, dst_y0 * dst_pitch);
            }
            if (dst_y1 < (int)dst_h) {
                std::memset(dst + dst_y1 * dst_pitch, 0, (dst_h - dst_y1) * dst_pitch);
            }

            if (target_w > 0 && target_h > 0) {
                // Clear left and right pillarbox margins on rows where video is drawn
                if (dst_x0 > 0 || dst_x1 < (int)dst_w) {
                    for (int dy = 0; dy < target_h; dy++) {
                        uint8_t* row = dst + (dst_y0 + dy) * dst_pitch;
                        if (dst_x0 > 0) std::memset(row, 0, dst_x0 * 4);
                        if (dst_x1 < (int)dst_w) std::memset(row + dst_x1 * 4, 0, (dst_w - dst_x1) * 4);
                    }
                }

                // Fast path: 1:1 unscaled blit (e.g. 640x480 -> 640x480)
                if (target_w == (int)src_w && target_h == (int)src_h) {
                    for (int dy = 0; dy < target_h; dy++) {
                        const uint8_t* s_row = src + dy * src_pitch;
                        uint8_t* d_row = dst + (dst_y0 + dy) * dst_pitch + dst_x0 * 4;

                        for (int dx = 0; dx < target_w; dx += 2) {
                            int y0 = s_row[0];
                            int u  = s_row[1];
                            int y1 = s_row[2];
                            int v  = s_row[3];
                            s_row += 4;

                            int c0 = y0 - 16;
                            int c1 = y1 - 16;
                            int d_val = u - 128;
                            int e_val = v - 128;

                            int b_term = 516 * d_val + 128;
                            int g_term = -100 * d_val - 208 * e_val + 128;
                            int r_term = 409 * e_val + 128;

                            int b0 = (298 * c0 + b_term) >> 8;
                            int g0 = (298 * c0 + g_term) >> 8;
                            int r0 = (298 * c0 + r_term) >> 8;

                            d_row[0] = (uint8_t)(b0 < 0 ? 0 : (b0 > 255 ? 255 : b0));
                            d_row[1] = (uint8_t)(g0 < 0 ? 0 : (g0 > 255 ? 255 : g0));
                            d_row[2] = (uint8_t)(r0 < 0 ? 0 : (r0 > 255 ? 255 : r0));
                            d_row[3] = 255;

                            int b1 = (298 * c1 + b_term) >> 8;
                            int g1 = (298 * c1 + g_term) >> 8;
                            int r1 = (298 * c1 + r_term) >> 8;

                            d_row[4] = (uint8_t)(b1 < 0 ? 0 : (b1 > 255 ? 255 : b1));
                            d_row[5] = (uint8_t)(g1 < 0 ? 0 : (g1 > 255 ? 255 : g1));
                            d_row[6] = (uint8_t)(r1 < 0 ? 0 : (r1 > 255 ? 255 : r1));
                            d_row[7] = 255;

                            d_row += 8;
                        }
                    }
                } else {
                    // Scaled blit fallback
                    for (int dy = 0; dy < target_h; dy++) {
                        int sy = dy * (int)src_h / target_h;
                        if (sy >= (int)src_h) sy = (int)src_h - 1;

                        const uint8_t* s_row = src + sy * src_pitch;
                        uint8_t* d_row = dst + (dst_y0 + dy) * dst_pitch + dst_x0 * 4;

                        for (int dx = 0; dx < target_w; dx++) {
                            int sx = dx * (int)src_w / target_w;
                            if (sx >= (int)src_w) sx = (int)src_w - 1;

                            int pair = sx >> 1;
                            const uint8_t* p = s_row + pair * 4;
                            int y_val = (sx & 1) ? p[2] : p[0];
                            int u_val = p[1];
                            int v_val = p[3];

                            int c = y_val - 16;
                            int d_val = u_val - 128;
                            int e_val = v_val - 128;

                            int b = (298 * c + 516 * d_val + 128) >> 8;
                            int g = (298 * c - 100 * d_val - 208 * e_val + 128) >> 8;
                            int r = (298 * c + 409 * e_val + 128) >> 8;

                            uint8_t* out = d_row + dx * 4;
                            out[0] = (uint8_t)(b < 0 ? 0 : (b > 255 ? 255 : b));
                            out[1] = (uint8_t)(g < 0 ? 0 : (g > 255 ? 255 : g));
                            out[2] = (uint8_t)(r < 0 ? 0 : (r > 255 ? 255 : r));
                            out[3] = 255;
                        }
                    }
                }
            }

            // Synchronize all other buffers in the swapchain (e.g. g_buffers[0]) with the exact same
            // rendered video frame so that when D3DDevice_Swap presents buffers on ticks where XmvGetNextFrame
            // has no new frame, the swapchain presents the current frame instead of an older frame.
            // This completely eliminates video flickering, jitter, and ghosting!
            {
                std::lock_guard<std::recursive_mutex> lock(d3d::Lock());
                const size_t copy_bytes = static_cast<size_t>(dst_pitch) * dst_h;
                const uint32_t buf_count = d3d::BufferCount();

                for (uint32_t i = 0; i < buf_count; ++i) {
                    const uint32_t buf = d3d::Buffer(i);
                    if (!buf || buf == rt) {
                        continue;
                    }

                    const uint32_t other_data = X86_MEM32(buf + 4);
                    if (!other_data) {
                        continue;
                    }

                    const uint32_t other_size = X86_MEM32(buf + 16);
                    const uint32_t other_h = ((other_size >> 12) & 0xFFF) + 1;
                    const uint32_t other_pitch = (((other_size >> 24) & 0xFF) + 1) * 64;
                    if (other_pitch != dst_pitch || other_h != dst_h) {
                        continue;
                    }

                    const uint32_t other_va = (other_data < 0x04000000) ? (0x80000000 | other_data) : other_data;
                    uint8_t* other_dst = base + other_va;
                    std::memcpy(other_dst, dst, copy_bytes);
                    gpu::MarkDirty(buf);
                }

                gpu::MarkDirty(rt);
            }
        }
    }

    ctx.eax = 0; // D3D_OK
    return true;
}

// sub_0045B420: DirectSound stream track parameter updater
// On null track / sound cue, avoids reading past null pointer
bool FixSoundNull45B420(X86Context& ctx, uint8_t* base) {
    (void)base;
    uint32_t track = X86_MEM32(ctx.esp + 4);
    if (!track) {
        ctx.eax = 0;
        return true;
    }
    uint32_t inner = X86_MEM32(track + 0x10);
    if (!inner) {
        ctx.eax = 0;
        return true;
    }
    return false;
}

// sub_0045B551: DirectSound stream track flag updater
// On null track / sound cue, avoids reading past null pointer
bool FixSoundNull(X86Context& ctx, uint8_t* base) {
    uint32_t track = X86_MEM32(ctx.esp + 4);
    if (!track) {
        ctx.eax = 0;
        return true;
    }
    uint32_t inner = X86_MEM32(track + 0x10);
    if (!inner) {
        ctx.eax = 0;
        return true;
    }
    return false;
}

// sub_004625C5: IUnknown::AddRef helper in audio engine
// Defensive check against null / uninitialized vtable pointer
bool FixSoundAddRef(X86Context& ctx, uint8_t* base) {
    uint32_t obj = X86_MEM32(ctx.esp + 4);
    if (!obj || !X86_MEM32(obj)) {
        ctx.eax = obj;
        return true;
    }
    return false;
}

// sub_0045F2D8: DirectSound channel/voice allocation helper
// Ecx is this pointer. If null or invalid, returns DSERR_BUFFERTOOSMALL / DSERR_ALLOCATED
bool FixSoundNullTrack(X86Context& ctx, uint8_t* base) {
    (void)base;
    if (!ctx.ecx) {
        ctx.eax = 0x88780032;
        return true;
    }
    uint32_t arg0 = X86_MEM32(ctx.esp + 4);
    if (!arg0 || !X86_MEM32(arg0 + 0x70)) {
        ctx.eax = 0x88780032;
        return true;
    }
    return false;
}

// sub_0045C87A: IDirectSoundBuffer_SetNotificationPositions
// HLE stub returning S_OK (0) so guest code doesn't touch uninitialized voice internals
bool FixSetNotificationPositions(X86Context& ctx, uint8_t* base) {
    (void)base;
    ctx.eax = 0; // DS_OK
    return true;
}

// sub_0045691C: XACT track / cue method (ret 0x08, thiscall)
// Defensive check if ecx is null
bool FixXactTrackNull(X86Context& ctx, uint8_t* base) {
    (void)base;
    if (!ctx.ecx) {
        ctx.eax = 0;
        return true;
    }
    return false;
}

// sub_004568D3: XACT track / cue method (ret, thiscall)
// Defensive check if ecx is null
bool FixXactTrackNull2(X86Context& ctx, uint8_t* base) {
    (void)base;
    if (!ctx.ecx) {
        ctx.eax = 0;
        return true;
    }
    return false;
}

// sub_003F4191: XOnlineGetUsers
// If XOnline is not initialized or no registered users, return S_OK with *pdwUsers = 0
bool FixXOnlineGetUsers(X86Context& ctx, uint8_t* base) {
    if (!ctx.ecx || !X86_MEM32(0x007602C0)) {
        uint32_t pdwUsers = X86_MEM32(ctx.esp + 8);
        if (pdwUsers) {
            X86_MEM32(pdwUsers) = 0;
        }
        ctx.eax = 0; // S_OK
        return true;
    }
    return false;
}

// sub_0034D9DC: UIX container assignment
// Defensive check against null container pointer
bool FixUIXSetContainer(X86Context& ctx, uint8_t* base) {
    uint32_t obj = X86_MEM32(ctx.esp + 4);
    uint32_t val = X86_MEM32(ctx.esp + 8);
    if (!val || !obj) {
        ctx.eax = 0x80070057; // E_INVALIDARG
        return true;
    }
    X86_MEM32(obj + 8) = val;
    ctx.eax = 0;
    return true;
}

// sub_003C0140: Vertex shader state application
// Guard against null CDevice_VertexShader. If device or shader pointer is null, return immediately.
bool FixShaderNull003C0140(X86Context& ctx, uint8_t* base) {
    (void)base;
    uint32_t dev = ctx.ecx;
    if (!dev) return true;
    uint32_t vs = X86_MEM32(dev + 0x794u);
    if (!vs) {
        return true;
    }
    return false;
}

// Unreal Engine 2 cooperative script fiber scheduler support
// UE2 uses a custom fiber scheduler (sub_000EE130) that switches stacks and saves/restores
// registers across sleep/yield calls. In recompiled code, fiber yields transfer control back to
// the scheduler via jmp 0x000EE16E. We use a C++ exception to unwind the host call stack back
// to the scheduler frame cleanly.
struct FiberYieldException {};
static thread_local int t_fiber_depth = 0;

void FixFiberYield(X86Context& ctx, uint8_t* base) {
    (void)ctx;
    (void)base;
    if (t_fiber_depth > 0) {
        throw FiberYieldException{};
    }
}

bool FixFiberScheduler(X86Context& ctx, uint8_t* base) {
    // 1. Emulate prologue of sub_000EE130
    X86_PUSH32(ctx.ebp);
    ctx.ebp = ctx.esp;
    X86_PUSH32(ctx.ecx);
    X86_PUSH32(ctx.ebx);
    X86_PUSH32(ctx.esi);
    X86_PUSH32(ctx.edi);

    uint32_t s = ctx.esp;
    X86_PUSH32(ctx.eax);
    X86_PUSH32(ctx.ecx);
    X86_PUSH32(ctx.edx);
    X86_PUSH32(ctx.ebx);
    X86_PUSH32(s);
    X86_PUSH32(ctx.ebp);
    X86_PUSH32(ctx.esi);
    X86_PUSH32(ctx.edi);

    uint32_t flags = ctx.cf | 2u | (ctx.pf << 2) | (ctx.zf << 6) | (ctx.sf << 7) | 0x200u |
                     (ctx.df << 10) | (ctx.of << 11) | ctx.xflags;
    X86_PUSH32(flags);

    ctx.eax = 0xEE16Eu;
    X86_MEM32(0x67C214u) = ctx.eax;
    X86_MEM32(0x67C224u) = ctx.esp;

    uint32_t arg0 = X86_MEM32(ctx.ebp + 0x8u);

    t_fiber_depth++;
    try {
        if (arg0 != 0) {
            uint32_t arg1 = X86_MEM32(ctx.ebp + 0xCu);
            ctx.ecx = arg1;
            X86_PUSH32(0xEE158u);
            x86_icall(ctx, base, 0x0004AAD0u);
            uint32_t fiber_obj = ctx.eax;
            X86_MEM32(ctx.ebp - 4) = fiber_obj;
            uint32_t vtable = X86_MEM32(fiber_obj);
            uint32_t fn = X86_MEM32(vtable + 4);
            ctx.ecx = fiber_obj;
            X86_PUSH32(0xEE166u);
            x86_icall(ctx, base, fn);
        } else {
            uint32_t resume_target = X86_MEM32(0x67C218u);
            x86_icall(ctx, base, resume_target);
        }
    } catch (const FiberYieldException&) {
        // Fiber yielded or slept; unwound cleanly to scheduler frame
    }
    t_fiber_depth--;

    // 2. on_true = 0x000EE166 jumps to loc_000EE166 which calls sub_000EE16E(ctx, base)
    // to pop flags, registers, frame pointer, and ret back to sub_000EEC00.
    return true;
}
