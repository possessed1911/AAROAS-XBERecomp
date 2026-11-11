# America's Army: Rise of a Soldier — PC Recomp

An unofficial native PC port of the original Xbox tactical shooter **America's Army: Rise of a Soldier** (Title ID `55530043`, XDK `5849`), statically recompiled for 64-bit Windows with a native **Direct3D 12** renderer, **XAudio2** spatial audio, modern **Mouse & Keyboard FPS controls**, and **Online Multiplayer** via XLink Kai and Direct IP.

Built using the [Xbox XBE Recomp](https://github.com/TGP482/XboxXBERecomp) framework.

> [!NOTE]
> This project contains **no game assets**. You must provide legally acquired files from your own retail Xbox copy of the game (as extracted files or a disc `.iso`).

---

## Table of Contents

- [About the Game](#about-the-game)
- [Key Features](#key-features)
- [Controls](#controls)
  - [Mouse & Keyboard (PC FPS)](#mouse--keyboard-pc-fps)
  - [Controller (Gamepad)](#controller-gamepad)
- [Video Playback & Presentation](#video-playback--presentation)
- [Multiplayer & Online Play](#multiplayer--online-play)
  - [Method 1: XLink Kai (Global Matchmaking)](#method-1-xlink-kai-global-matchmaking)
  - [Method 2: Direct IP / VPN](#method-2-direct-ip--vpn)
  - [Online Services Note (Insignia vs. XLink Kai)](#online-services-note-insignia-vs-xlink-kai)
- [Configuration (`settings.toml`)](#configuration-settingstoml)
- [Installation & Running](#installation--running)
- [Building from Source](#building-from-source)
- [Technical Architecture & Fixes](#technical-architecture--fixes)
- [Troubleshooting & FAQ](#troubleshooting--faq)
- [Credits & Legal](#credits--legal)

---

## About the Game

Originally developed by the **U.S. Army**, **Ubisoft**, and **Secret Level** and released for the original Xbox in November 2005, *America's Army: Rise of a Soldier* is an authentic, squad-oriented tactical first-person shooter. 

Unlike conventional arcade shooters, *Rise of a Soldier* emphasizes authentic military protocols:
- **Career Progression**: Follow a recruit's career from initial Basic Rifle Marksmanship (BRM), obstacle courses, and Military Operations on Urban Terrain (MOUT) to elite Special Forces deployments.
- **MOS Specializations**: Train and deploy across different Military Occupational Specialties:
  - **Rifleman** (M16A2 / M4A1 assault rifles)
  - **Grenadier** (M203 40mm grenade launcher)
  - **Automatic Rifleman** (M249 SAW)
  - **Sniper** (M24 SWS, SPR)
- **Squad Command System**: Lead fireteams in the field with squad commands: order bounding overwatch, tactical movement, suppression fire, and breach & clear maneuvers.
- **Realistic Ballistics & ROE**: Strict adherence to the Rules of Engagement (ROE), authentic recoil patterns, breathing sway, stance stability (standing, crouched, prone), and suppression dynamics.

---

## Key Features

### 🎮 Native Mouse & Keyboard FPS Controls
- **True Mouse Look**: Smooth, sub-pixel mouse movement translated to in-game camera rotation with console deadzone evasion and micro-stutter filtering.
- **Cursor Management**: Automatically locks and hides the cursor during gameplay. Press **`F1`** at any time to release the cursor, or left-click into the window to recapture.
- **Configurable Look**: Adjust mouse sensitivity multiplier and invert vertical look in `settings.toml`.
- **Full PC FPS Bindings**: WASD movement, Space jump/vault, Left Shift sprint, C/Ctrl crouch/prone, R reload, Q/F/Mouse Wheel weapon cycle, and G grenade.

### 🌐 Online Multiplayer (System Link & XLink Kai)
- **XLink Kai Matchmaking**: Play online worldwide through the [XLink Kai](https://teamxlink.co.uk/) tunneling client with no Xbox Live servers or accounts required.
- **Direct IP Join**: Connect directly across different networks or over the Internet using the `join_ip` setting in `settings.toml`.
- **LAN & Virtual LAN**: Fully compatible with home local area networks and VPNs (ZeroTier, Tailscale, Hamachi, Radmin VPN).
- **Winsock Enhancements**: Hardware UDP broadcast support (`SO_BROADCAST`), port reuse (`SO_REUSEADDR`), and subnet broadcast resolution (`192.168.x.255`).

### 🖥️ Direct3D 12 Graphics Engine & Video Playback
- **Direct3D 12 Renderer**: Native hardware rasterization and swapchain presentation.
- **Arbitrary Resolution Scaling**: Configurable internal render resolution (`render_percent`) up to 4K and beyond.
- **High Frame-Rate Support**: 60 FPS, 120 FPS, 144 FPS, or uncapped (`fps_cap = 0`).
- **Widescreen Presentation**: True 16:9 aspect ratio support.
- **Texture Enhancements**: Up to 16x Anisotropic Filtering, custom texture replacement, and texture dumping.
- **Hardware Video Overlay Emulation**: Re-enabled `.xmv` movie playback (intro logos, cutscenes, soldier career diaries) converted from YUY2 to 32-bit BGRA with BT.601 color space conversion.
- **Zero-Flicker Swapchain Synchronization**: Double-buffered swapchain synchronization completely eliminates frame oscillation, judder, and ghosting artifacts.
- **Video Skipping**: Skip intro logos and cutscenes at any time using `Space`, `Enter`, `Escape`, `E`, or Gamepad `A` / `Start` (protected by a 15-frame debounce guard).

### 🔊 Spatial 3D Audio
- Powered by **XAudio2** with multi-channel and stereo outputs.
- Complete 3D Head-Related Transfer Function (HRTF) audio table initialization for authentic positional audio.

### 🎮 Gamepad & Controller Support
- Native **SDL3** controller backend supporting Xbox, PlayStation (DualShock / DualSense), and Nintendo Switch controllers.
- Full analog trigger sensitivity, dual-motor rumble feedback, and hot-plugging.

---

## Controls

### Mouse & Keyboard (PC FPS)

| Action | PC Key / Mouse | Controller Equivalent |
| :--- | :--- | :--- |
| **Look / Aim** | **Mouse Movement** | Right Analog Stick |
| **Fire** | **Left Mouse Button (LMB)** | Right Trigger (RT) |
| **Aim Down Sights (ADS)** | **Right Mouse Button (RMB)** | Left Trigger (LT) |
| **Melee / Steady Aim / Zoom** | **Middle Mouse Button (MMB)** or `V` | Right Stick Click (RS / R3) |
| **Cycle Weapon / Sidearm** | **Mouse Wheel Scroll** or `Q` / `F` / `1` / `2` | Y Button |
| **Movement / Strafe** | `W` / `A` / `S` / `D` | Left Analog Stick |
| **Vault / Jump / Action / Select** | `Space` or `E` | A Button |
| **Crouch / Prone / Cancel** | `C` or `Left Ctrl` | B Button |
| **Reload** | `R` | X Button |
| **Grenade / Special Equipment** | `G` or `3` | White Button |
| **Fire Mode Selector** | `B` or `4` or `X` | Black Button |
| **Sprint** | `Left Shift` | Left Stick Click (LS / L3) |
| **Objectives / Scoreboard** | `Tab` | Back Button |
| **Pause / In-Game Menu** | `Escape` | Start Button |
| **Confirm / Select** | `Enter` | Start Button / A Button |
| **Squad Commands (D-Pad)** | Arrow Keys (`↑` `↓` `←` `→`) or `Z` / `X` | D-Pad Buttons |
| **Toggle Cursor Lock** | **`F1`** | *(Toggles mouse lock on/off)* |

> [!TIP]
> Pressing **`F1`** frees the mouse cursor so you can navigate to other monitors or windows. Clicking anywhere inside the game window automatically re-engages mouse lock.

### Controller (Gamepad)

| Button | Action |
| :--- | :--- |
| **Left Stick** | Move / Strafe |
| **Right Stick** | Look / Aim |
| **Right Trigger (RT)** | Fire |
| **Left Trigger (LT)** | Aim Down Sights (ADS) |
| **Left Stick Click (LS)** | Sprint |
| **Right Stick Click (RS)** | Melee / Steady Aim / Sniper Zoom |
| **A Button** | Vault / Jump / Use / Menu Select |
| **B Button** | Crouch / Prone / Menu Cancel |
| **X Button** | Reload |
| **Y Button** | Cycle Weapon |
| **White Button** | Throw Grenade / Equipment |
| **Black Button** | Toggle Fire Mode (Semi / Burst / Auto) |
| **D-Pad** | Issue Squad Fireteam Orders |
| **Start** | Pause Menu |
| **Back** | Objectives / Scoreboard |

---

## Video Playback & Presentation

Original Xbox hardware used an asynchronous hardware video overlay plane to scan out video frames independently of the 3D render pipeline. On modern PC hardware with Direct3D 12:

1. **Overlay Interception**:
   - The game's video player calls (`sub_002F4540` and `sub_00428661`) are intercepted.
   - Decoded YUY2 video streams are converted to 32-bit BGRA using BT.601 color conversion equations:
     $$\begin{aligned}
     R &= \text{clamp}\big((298 \cdot C + 409 \cdot E + 128) \gg 8\big) \\
     G &= \text{clamp}\big((298 \cdot C - 100 \cdot D - 208 \cdot E + 128) \gg 8\big) \\
     B &= \text{clamp}\big((298 \cdot C + 516 \cdot D + 128) \gg 8\big)
     \end{aligned}$$
     where $C = Y - 16$, $D = U - 128$, $E = V - 128$.
2. **Swapchain Buffer Synchronization**:
   - Videos are encoded at 24 or 30 FPS, while display presentation flips at 60 Hz.
   - On presentation ticks where no new video frame has arrived, `D3DDevice_Swap` rotates the swapchain buffers.
   - To prevent alternating between the new frame and older frames (which caused extreme 60 Hz flickering and ghosting), `FixOverlayUpdate` automatically clones the current decoded frame to all swapchain buffers under a mutex lock and notifies the GPU through dirty tracking (`gpu::MarkDirty`).
   - This delivers silky-smooth 60 Hz presentation with clean 2:2 / 3:2 pulldown.
3. **Skip Support**:
   - Videos can be skipped at any point after a 15-frame grace period (~0.25 seconds) by pressing `Space`, `Enter`, `Escape`, `E`, or gamepad `A` / `Start`.
   - Supported videos include `ESRB.xmv`, `UbisoftLogo.xmv`, `SLLogo.xmv`, `DemoMode.xmv`, mission briefings, and cutscenes.

---

## Multiplayer & Online Play

The original Xbox version of *America's Army: Rise of a Soldier* includes System Link multiplayer for up to 16 players across various adversarial and co-op game modes.

### Method 1: XLink Kai (Global Matchmaking)

[XLink Kai](https://teamxlink.co.uk/) is a free tunneling client that allows console and recompiled System Link games to be played across the globe over the Internet.

1. Download and install **XLink Kai** from [https://teamxlink.co.uk/](https://teamxlink.co.uk/).
2. Run the XLink Kai client and log into your account.
3. In the XLink Kai web interface, navigate to:  
   `Game Arenas` ➔ `Microsoft Xbox` ➔ `Action / Shooter` ➔ `America's Army: Rise of a Soldier`.
4. Launch `aa_roas.exe`.
5. In the game's main menu, select **Multiplayer** ➔ **System Link**.
6. Select **Host** to create a lobby or **Search** to discover other players in the arena!

### Method 2: Direct IP / VPN

You can play directly with friends without XLink Kai by connecting via IP:

1. Open `settings.toml` in a text editor.
2. In the `join_ip` field, enter the host's IP address:
   ```toml
   join_ip = "192.168.1.100"   # LAN or VPN IP (ZeroTier, Hamachi, Tailscale, Radmin)
   # Or host's public IP address (requires port forwarding UDP 1255 on host router):
   # join_ip = "203.0.113.42"
   ```
3. The host starts the match via **Multiplayer** ➔ **System Link** ➔ **Host**.
4. The client selects **Multiplayer** ➔ **System Link** ➔ **Search**. The game queries the host directly and connects.

### Online Services Note (Insignia vs. XLink Kai)

> [!NOTE]
> **Insignia** is an Xbox Live server replacement that emulates Microsoft's proprietary online matchmaking servers, authentication tickets, and Kerberos security gateways.
>
> In contrast, **System Link** (used by *Rise of a Soldier* for LAN and tunnel play) uses standard peer-to-peer UDP networking. Because this recompilation directly hooks native Windows Winsock with UDP broadcast emulation, **XLink Kai** and **Direct IP** work out of the box with zero external server dependencies, user registrations, or account credentials.

---

## Configuration (`settings.toml`)

All game settings are stored in `settings.toml` beside `aa_roas.exe`.

```toml
# Display & Video
display_mode = "windowed"       # "fullscreen", "borderless", "windowed"
width = 1280                    # Horizontal resolution (0 for desktop native)
height = 720                    # Vertical resolution (0 for desktop native)
render_percent = 100            # Internal resolution percentage (e.g. 100, 150, 200 for 4K)
fps_cap = 60                    # Frame rate cap (0 for uncapped, or 60, 120, 144)
vsync = true
anisotropic_filtering = 16      # Texture filtering quality (0 to 16)
custom_textures = true          # Enable texture replacements from textures\replacement\
dump_textures = false           # Dump textures to textures\dumps\
texture_dump_format = 0         # 0 = DDS, 1 = PNG

# Audio
audio_output = 0                # 0 = Stereo / Surround, 1 = Mono

# Mouse & Keyboard Controls
mouse_sensitivity = 1.0         # Mouse look sensitivity multiplier (e.g. 0.5 to 2.5)
mouse_invert_y = false          # Set to true to invert vertical look (airplane style)

# Multiplayer
join_ip = ""                    # Host IP address for Direct IP System Link
```

---

## Installation & Running

### Requirements
- **OS**: Windows 10 or 11 (64-bit)
- **GPU**: Direct3D 12 compatible graphics card (DirectX Feature Level 11_0+)
- **Storage**: ~4 GB free disk space for game assets and recompiled binaries

### Prebuilt Release (`aa_roas.zip`)
1. Download the latest `aa_roas.zip` from [GitHub Releases](https://github.com/possessed1911/AAROAS-XBERecomp/releases) and extract it to a folder.
2. Place your legally acquired game files into the `assets` folder beside `aa_roas.exe` (either as an uncompressed `.iso` image or extracted files containing `default.xbe`).
3. Run `aa_roas.exe` to launch immediately (`aa_roas.dll` is precompiled and bundled in the release, so no local first-run compilation is needed).
4. A custom boot splash (`splash.png`) is bundled beside `aa_roas.exe` and can be replaced with your own `.png` or `.bmp` image.

---

## Building from Source

### 1. Prerequisites
- [Git](https://git-scm.com/)
- [LLVM / Clang 18+](https://releases.llvm.org/) (`clang++.exe`, `lld-link.exe`) added to `PATH`
- [CMake 3.25+](https://cmake.org/) and [Ninja](https://ninja-build.org/) added to `PATH`
- Visual Studio 2022 or Build Tools with the **Desktop development with C++** workload

### 2. Clone & Prepare Game Assets
Clone the repository and link or copy your extracted game folder into `assets`:
```cmd
git clone https://github.com/possessed1911/AAROAS-XBERecomp.git
cd AAROAS-XBERecomp
mklink /J assets "D:\Games\AmericasArmy"
```

### 3. Compile
To perform a complete clean build:
```cmd
build.bat
```
For subsequent rapid builds after modifying code:
```cmd
build_fast.bat
```
To gather `aa_roas.exe`, `aa_roas.dll`, runtime DLLs, and `splash.png` into a distributable `aa_roas.zip` release archive:
```cmd
release.bat
```
The compiled binaries (`aa_roas.exe` and `aa_roas.dll`) are placed in `out\build\release\`.

---

## Technical Architecture & Fixes

This recompiled port solves several critical Xbox hardware and engine quirks:

1. **Direct3D 8 NV2A Video Overlay Interception & Swapchain Sync (`FixOverlayActive` / `FixOverlayUpdate`)**:
   - The Xbox video playback engine (`sub_002F4540` / `sub_00428661`) accesses NV2A-specific hardware overlay registers and displays frames asynchronously. Hooks intercept these calls, converting YUY2 frames to 32-bit BGRA with color space conversion and software blending into the active render target.
   - **Flicker-Free Presentation**: When playing 24 or 30 FPS videos on a 60 Hz display, `D3DDevice_Swap` continues to flip buffers at 60 Hz even on ticks where no new video frame was decoded. `FixOverlayUpdate` automatically synchronizes all swapchain buffers under a mutex lock and triggers GPU re-upload dirty tracking (`gpu::MarkDirty`), preventing alternating buffer judder, double-image ghosting, or screen tearing.
2. **Video Playback & Debounced Skipping (`FixMovieUpdate`)**:
   - Manages playback of `.xmv` cutscene threads. Implements debounced skipping on Space, Enter, Escape, E, or Gamepad A/Start after a 15-frame safety period to prevent skipping unintended scenes.
3. **Dynamic Vertex Shader Descriptor Emulation (`FixShaderNull003C0140`)**:
   - Emulates the Xbox XDK `CDevice_VertexShader` state table, preventing null-pointer dereferences during vertex shader state switches.
4. **3D HRTF DirectSound Function Table (`InitHRTFTable`)**:
   - Original Xbox DirectSound uses hardware 3D Head-Related Transfer Functions (`0x0047952C`). The port initializes the 3D HRTF function dispatch table at runtime, resolving indirect call traps.
5. **DirectSound Null Track Updater Protection (`FixSoundNull45B420` & `FixSoundNull`)**:
   - Defensively catches and bypasses null track descriptor accesses in the sound streaming engine, preventing memory access violations during sound cue transitions.
6. **XNet Winsock Broadcast & Discovery Emulation**:
   - Bridges Xbox network sockets directly to native Windows Winsock with `SO_BROADCAST` and `SO_REUSEADDR` permissions, allowing System Link UDP discovery across local subnets and tunneling adapters.
7. **Mouse Look Deadzone Evasion Algorithm**:
   - Original console thumbsticks require a minimum physical deflection before registering motion (deadzone). The recompilation translates mouse $(\Delta x, \Delta y)$ pulses into analog stick values using a deadzone evasion offset ($7200$) and an exponential smoothing filter:
     $$S_{\text{new}} = 0.25 \cdot S_{\text{old}} + 0.75 \cdot S_{\text{target}}$$
     with rapid decay on stop, yielding responsive, 1:1 mouse aiming without twitching or stick drag.
8. **Automated Headless Test Runner (`AA_AUTO_START`)**:
   - Setting the environment variable `AA_AUTO_START=1` enables an automated sequence that skips movies and advances through menus for CI/CD and regression testing.

---

## Troubleshooting & FAQ

<details>
<summary><b>The game crashes immediately on startup. What should I check?</b></summary>

1. Verify that `assets/default.xbe` exists and has SHA-1 checksum `f1fc23d24706d058ba1db53e2426a0f41767599c`.
2. Ensure your GPU supports Direct3D 12 (Feature Level 11_0 or higher).
3. Check the latest log file generated in `out/build/release/logs/` for specific error messages.
</details>

<details>
<summary><b>The mouse cursor is visible and looking around does not work.</b></summary>

- Left-click anywhere inside the game window, or press **`F1`** to re-engage mouse capture.
- If you have multiple monitors, mouse capture locks the cursor to the client window boundaries.
</details>

<details>
<summary><b>How do I change the display mode or internal resolution?</b></summary>

- Open `settings.toml` beside `aa_roas.exe`.
- Change `display_mode` to `"fullscreen"`, `"borderless"`, or `"windowed"`.
- Set `render_percent = 200` to render at $2\times$ internal resolution (e.g. 4K rendering on a 1080p display).
</details>

<details>
<summary><b>System Link server is not found in Multiplayer.</b></summary>

1. If playing over LAN, ensure Windows Firewall allows UDP traffic for `aa_roas.exe` on private networks.
2. If playing over XLink Kai, make sure the XLink Kai client is running, you are logged in, and you have joined the *America's Army: Rise of a Soldier* arena before launching the game.
3. If connecting via Direct IP, enter the host's IP in `settings.toml` under `join_ip = "..."` and make sure UDP port 1255 is forwarded on the host's router.
</details>

---

## Credits & Legal

- **Developers**: Developed by the **United States Army**, **Ubisoft**, and **Secret Level** (2005).
- **[Xbox XBE Recomp](https://github.com/TGP482/XboxXBERecomp)**: Framework for static recompilation of original Xbox binaries.
- **[XenonRecomp](https://github.com/hedge-dev/XenonRecomp)**: Static recompilation inspiration and concepts.
- **Libraries**:
  - [Zydis](https://github.com/zyantific/zydis) x86 instruction decoder.
  - [SDL3](https://github.com/libsdl-org/SDL) for modern gamepad and input handling.
  - [toml++](https://github.com/marzer/tomlplusplus) for configuration parsing.
  - [Dear ImGui](https://github.com/ocornut/imgui) for in-game diagnostic and interface overlay.

### Disclaimer
*America's Army: Rise of a Soldier* is the intellectual property of the United States Army and Ubisoft. This repository does not distribute copyrighted game assets or proprietary code. It is an independent open-source reverse engineering and recompilation project intended for educational, preservation, and compatibility purposes.
