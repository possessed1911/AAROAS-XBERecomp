# Contributing to America's Army: Rise of a Soldier PC Recomp

Thank you for your interest in contributing! This project is an open-source static recompilation of the original Xbox game *America's Army: Rise of a Soldier* for 64-bit Windows.

---

## ⚠️ Essential Rule: No Game Assets

**Never commit or submit game assets, proprietary code, or extracted game files.**
- This repository contains only the recompilation source code, hooks, runtime SDK glue, and build configurations.
- Any pull request containing copyrighted assets (such as `.xbe` files, `.xmv` videos, `.xpr` textures, `.pkg` UI archives, or game scripts) will be immediately closed.

---

## Development & Build Workflow

### Prerequisites
- Windows 10/11 (64-bit)
- Visual Studio 2022 or Build Tools with the **Desktop development with C++** workload
- LLVM / Clang 18+ (`clang++.exe`, `lld-link.exe`)
- CMake 3.25+ and Ninja

### Fast Iteration
1. Link your retail game folder to `assets`:
   ```cmd
   mklink /J assets "D:\path\to\extracted_game"
   ```
2. Build incrementally using `build_fast.bat`:
   ```cmd
   cmd /c build_fast.bat
   ```
3. Test your build:
   ```cmd
   out\build\release\aa_roas.exe
   ```

---

## Coding Standards

- **Language Standard**: Modern **C++20** (`/std:c++20`).
- **Thread Safety**: Any code accessing shared runtime state (such as the D3D8 swapchain, GPU textures, audio streams, or memory mappings) across multiple threads must be protected by appropriate synchronization primitives (e.g. `d3d::Lock()`).
- **Memory Safety**:
  - Always validate pointers and guest virtual addresses before arithmetic or `memcpy`.
  - Check buffer dimensions and strides (`pitch == other_pitch && height == other_height`) before block memory transfers.
  - Guard array accesses with bounds checks.
- **Header Hygiene**: Use existing header declarations (e.g. `#include "gpu/texture.h"`) rather than ad-hoc manual forward declarations.
- **Formatting**: Keep code clean, readable, and consistent with the existing codebase style.

---

## Submitting Pull Requests

1. Fork the repository and create a feature branch (`git checkout -b feature/my-enhancement`).
2. Ensure your changes compile cleanly without compiler warnings (`build_fast.bat`).
3. Verify that the game boots and runs stably with zero regressions to input, video, audio, or multiplayer.
4. Write clear, descriptive commit messages.
5. Open a Pull Request detailing:
   - What problem is solved or what feature is added.
   - Root cause analysis (for bug fixes).
   - Verification evidence (e.g. log output, test runs).
