# Test Infrastructure & Specification: AAROAS-XBERecomp Cursor & Display Modes

## 1. Executive Summary

This document specifies the automated End-to-End (E2E) test infrastructure for verifying mouse cursor visibility management and Alt+Enter display mode toggling in **AAROAS-XBERecomp**. 

The test harness operates strictly as an **opaque-box** test suite, exercising the application externally via native Win32 subsystem APIs (window styles, cursor info, clipping rects, focus events, and keyboard input injection). It contains **47 automated test cases** distributed across four verification tiers, providing comprehensive coverage for user requirements R1, R2, and R3.

---

## 2. Test Philosophy & Design Methodologies

The test architecture is engineered to guarantee deterministic, reproducible, and non-invasive verification without modifying game runtime source code:

1. **Opaque-Box Testing**:
   - The test runner inspects the game strictly from the operating system's vantage point.
   - Verification is conducted through Win32 P/Invoke inspection of OS primitives (`HWND`, `GWL_STYLE`, `CURSORINFO`, `ClipCursor`, `WINDOWPLACEMENT`).
   - Does not hook or inject code into the target process address space.

2. **Requirement-Driven Verification**:
   - Directly maps to user requirements:
     - **R1 (Mouse Cursor Visibility & Window Focus)**: Cursor hidden in fullscreen and windowed gameplay; cursor visible and unclipped when unfocused/Alt-Tabbed; cursor re-hidden upon refocus.
     - **R2 (Display Mode Toggle via Alt + Enter)**: Seamless bidirectional toggle between borderless/fullscreen and windowed modes with position and geometry preservation.
     - **R3 (Release Prohibition)**: Zero remote git pushes or public release actions.

3. **Category-Partitioning**:
   - Input and state domains are partitioned into discrete equivalence classes:
     - **Display Modes**: Borderless Fullscreen (`WS_POPUP`) vs. Windowed (`WS_OVERLAPPEDWINDOW`).
     - **Window Focus States**: Focused Foreground vs. Defocused/Background (Alt-Tabbed, Desktop clicked, Minimized).
     - **Cursor States**: Visible (`CURSOR_SHOWING` set, valid `hCursor`) vs. Hidden (`CURSOR_SHOWING` cleared, `hCursor == NULL`), Clipped (`ClipCursor` bounds matching client rect) vs. Unclipped (`ClipCursor` spanning virtual desktop).
     - **Input Vectors**: Clean Alt+Enter, Rapid Alt+Enter bursts, Alt held with other keys (`Alt+W`, `Alt+S`, `Alt+Space`), Alt-Tab sequences.

4. **Boundary Value Analysis (BVA)**:
   - Tests boundary conditions:
     - Rapid consecutive toggles (50ms interval) to verify debounce and message pump stability.
     - Alt key hold durations (80ms single press vs. 300ms extended hold) to verify repeat key suppression (`lp & (1 << 30)` handling).
     - Edge-of-screen cursor positioning and window boundaries.
     - Off-screen prevention: verifying window rect remains within monitor work areas.

5. **Pairwise & Cross-Feature Interaction Testing**:
   - Multi-variate state transitions combining focus changes with mode switches:
     - Alt-Tab immediately followed by Alt+Enter while unfocused.
     - Abrupt focus loss occurring during a display mode transition.
     - Active mouse delta capture during window style reconfiguration.

6. **Workload & Lifecycle Testing (Tier 4)**:
   - Simulates complete end-to-end player journeys:
     - Booting into borderless mode -> verifying cursor suppression -> toggling to windowed -> Alt-Tabbing to browse desktop -> returning to game -> toggling back to borderless.
     - Autonomous gameplay loop progression under `AA_AUTO_START=1` verifying cursor suppression across intro movies, main menus, and mission gameplay.

---

## 3. Feature Inventory & Requirements Traceability

| Feature ID | Feature Description | Requirement Source | Tier 1 Tests | Total Tests (All Tiers) |
|---|---|---|---|---|
| **F1** | Cursor Hidden in Borderless/Fullscreen Mode | ORIGINAL_REQUEST R1 / PROJECT.md F1 | 5 tests (`T1-F1-01` .. `T1-F1-05`) | 8 tests |
| **F2** | Cursor Hidden in Windowed Mode | ORIGINAL_REQUEST R1 / PROJECT.md F2 | 5 tests (`T1-F2-01` .. `T1-F2-05`) | 8 tests |
| **F3** | Cursor Visible and Free on Defocus | ORIGINAL_REQUEST R1 / PROJECT.md F3 | 5 tests (`T1-F3-01` .. `T1-F3-05`) | 9 tests |
| **F4** | Cursor Re-hidden on Window Refocus | ORIGINAL_REQUEST R1 / PROJECT.md F4 | 5 tests (`T1-F4-01` .. `T1-F4-05`) | 8 tests |
| **F5** | Alt+Enter Fullscreen/Borderless to Windowed | ORIGINAL_REQUEST R2 / PROJECT.md F5 | 5 tests (`T1-F5-01` .. `T1-F5-05`) | 9 tests |
| **F6** | Alt+Enter Windowed to Fullscreen/Borderless | ORIGINAL_REQUEST R2 / PROJECT.md F6 | 5 tests (`T1-F6-01` .. `T1-F6-05`) | 8 tests |
| **F7** | Window Placement, Geometry & Bounds Integrity | ORIGINAL_REQUEST R2 / PROJECT.md F7 | 5 tests (`T1-F7-01` .. `T1-F7-05`) | 6 tests |
| **F8** | Release Prohibition & Demo Integrity | ORIGINAL_REQUEST R3 / PROJECT.md F8 | Audit verification | Operational Gate |

---

## 4. Test Harness Architecture

### 4.1 Runner File & Entry Point
- **Script Path**: `scripts/test_e2e_cursor_display.ps1`
- **Execution Engine**: Microsoft PowerShell (v5.1+ / Core 7+) with native C# P/Invoke compilation via `Add-Type`.

### 4.2 Runner Parameters
| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Preset` | `string` | `"release"` | CMake preset under `out/build/<preset>` containing `aa_roas.exe` and `settings.toml`. |
| `-Tier` | `string[]` | `@("All")` | Selects tiers to execute: `"1"`, `"2"`, `"3"`, `"4"`, or `"All"`. |
| `-Feature` | `string[]` | `@("All")` | Filters Tier 1 feature tests: `"F1"` through `"F7"`, or `"All"`. |
| `-ReportPath` | `string` | `""` | File path to write Markdown formatted test execution results. |
| `-ListTests` | `switch` | `false` | Displays all 47 registered test cases and exits without executing. |
| `-TimeoutSeconds`| `int` | `15` | Maximum timeout in seconds for window launch and settle phases. |

### 4.3 Win32 P/Invoke Mechanics (`Win32Harness`)
The test runner embeds an in-memory C# static class `Win32Harness` defining Win32 structures and entry points:
- **Structures**:
  - `POINT`: `{ int x, int y }`
  - `RECT`: `{ int left, int top, int right, int bottom, Width, Height }`
  - `CURSORINFO`: `{ int cbSize, int flags, IntPtr hCursor, POINT ptScreenPos }`
  - `WINDOWPLACEMENT`: `{ length, flags, showCmd, ptMinPosition, ptMaxPosition, rcNormalPosition }`
  - `MONITORINFO`: `{ cbSize, rcMonitor, rcWork, dwFlags }`
- **Window Management APIs**:
  - `GetWindowLongPtrW`: Queries `GWL_STYLE` (`0x80000000` `WS_POPUP`, `0x00C00000` `WS_CAPTION`, `0x00CF0000` `WS_OVERLAPPEDWINDOW`).
  - `GetWindowRect` & `GetClientRect`: Validates outer framing vs. render canvas.
  - `ClientToScreen`: Translates client coordinates to desktop screen space.
  - `GetWindowPlacement`: Inspects persistent window restoration rect and show state.
  - `MonitorFromWindow` & `GetMonitorInfoW`: Validates screen bounds against the active display monitor.
  - `SetForegroundWindow`, `BringWindowToTop`, `SwitchToThisWindow`: Programmatic focus transitions.
  - `ShowWindow`: Minimization (`SW_MINIMIZE`) and restoration (`SW_RESTORE`).
- **Cursor & Clipping APIs**:
  - `GetCursorInfo`: Returns visibility flags (`CURSOR_SHOWING = 0x00000001`) and active cursor handle (`hCursor`).
  - `GetClipCursor` & `ClipCursor`: Evaluates cursor bounding restrictions.
- **Desktop Isolation & Safe Multi-Threading**:
  - `OpenInputDesktop`, `SetThreadDesktop`, and `CloseDesktop`: Win32 security isolation. To query cursor state and manipulate foreground focus across independent user sessions or elevation contexts, queries are dispatched inside dedicated STA threads configured with input desktop access.
- **Input Injection**:
  - `keybd_event`: Generates hardware-level key down/up events for `VK_MENU` (Alt), `VK_RETURN` (Enter), `VK_TAB` (Tab), and alphanumeric keys with accurate millisecond hold intervals.

### 4.4 Process Lifecycle & Environmental Isolation
- **Configuration Sandbox**:
  - Before execution, `settings.toml` in `out/build/<preset>` is backed up to `settings.toml.testbak`.
  - Mode switches and test mutations are applied cleanly.
  - Upon completion or premature test abort, `settings.toml` is restored and the backup removed.
- **Process Supervision**:
  - Spawns `aa_roas.exe` with `AA_AUTO_START=1` environment variable.
  - Locates main application window by enumerating process windows and matching class name `"aa_roas"`.
  - On cleanup (`finally` block), kills target process, restores cursor clipping (`ClipCursor(NULL)`), and settles input desktop state.

---

## 5. Complete Inventory of Automated Test Cases (47 Tests)

### Tier 1: Feature Coverage (35 Tests)

#### Feature F1: Cursor Hidden in Borderless/Fullscreen Mode (5 Tests)
1. **`T1-F1-01` — Borderless Window Style**: Asserts window style has `WS_POPUP` (`0x80000000`) and lacks `WS_CAPTION`.
2. **`T1-F1-02` — Borderless Monitor Geometry Coverage**: Asserts window rectangle width and height span 100% of the active monitor rect.
3. **`T1-F1-03` — Cursor Hidden on Borderless Boot**: Asserts `CURSORINFO.flags` has `CURSOR_SHOWING` cleared (`0`) or `hCursor == NULL` while game is focused.
4. **`T1-F1-04` — Cursor Clip Rect in Borderless**: Asserts `GetClipCursor` bounds match borderless client area dimensions.
5. **`T1-F1-05` — Cursor Hidden During Gameplay/Menus**: Asserts cursor remains continuously hidden during automated gameplay progression.

#### Feature F2: Cursor Hidden in Windowed Mode (5 Tests)
6. **`T1-F2-01` — Windowed Window Style**: Asserts window style has `WS_OVERLAPPEDWINDOW` (`0x00CF0000`) and has `WS_CAPTION`.
7. **`T1-F2-02` — Windowed Geometry Inside Desktop Bounds**: Asserts window rect is fully positioned within the desktop work area.
8. **`T1-F2-03` — Cursor Hidden in Windowed Mode**: Asserts cursor is completely hidden when game is focused in windowed mode.
9. **`T1-F2-04` — Cursor Clipping to Windowed Client Rect**: Asserts cursor clip rect strictly aligns with the windowed client rect.
10. **`T1-F2-05` — Windowed Gameplay Progression Cursor Suppression**: Asserts cursor remains hidden across frames during gameplay in windowed mode.

#### Feature F3: Cursor Visible and Free on Defocus (5 Tests)
11. **`T1-F3-01` — Defocus via Foreground Switch**: Yields foreground focus to desktop/shell and confirms focus leaves the game window.
12. **`T1-F3-02` — Cursor Clipping Released on Defocus**: Asserts `GetClipCursor` expands to full desktop dimensions upon defocus.
13. **`T1-F3-03` — Cursor Visible (Arrow) on Defocus**: Asserts `CURSORINFO.flags` has `CURSOR_SHOWING` active and valid `hCursor` handle.
14. **`T1-F3-04` — Defocus via Alt-Tab Key Sequence**: Sends synthetic Alt-Tab and confirms immediate cursor release and unclip.
15. **`T1-F3-05` — Cursor Free to Move Across Desktop**: Asserts cursor is unrestricted and not clamped to window center.

#### Feature F4: Cursor Re-hidden on Window Refocus (5 Tests)
16. **`T1-F4-01` — Refocus Game Window**: Programmatically restores foreground focus to the game window.
17. **`T1-F4-02` — Cursor Clip Re-engaged on Refocus**: Asserts cursor clip rect re-engages to game client boundaries.
18. **`T1-F4-03` — Cursor Re-hidden on Refocus**: Asserts cursor visibility is suppressed upon refocus.
19. **`T1-F4-04` — Mouse Look Re-engaged on Refocus**: Asserts capture state and relative mouse look readiness resume.
20. **`T1-F4-05` — Multi-Cycle Focus Toggle Consistency**: Executes 3 rapid defocus/refocus cycles and verifies capture consistency.

#### Feature F5: Alt+Enter Fullscreen/Borderless to Windowed Mode (5 Tests)
21. **`T1-F5-01` — Alt+Enter Keystroke in Borderless**: Dispatches synthetic `VK_MENU` + `VK_RETURN` while in borderless mode.
22. **`T1-F5-02` — Style Transition to WS_OVERLAPPEDWINDOW**: Asserts window style changes from `WS_POPUP` to `WS_OVERLAPPEDWINDOW`.
23. **`T1-F5-03` — Title Bar and Borders Present**: Asserts presence of `WS_CAPTION` and window sizing frame borders.
24. **`T1-F5-04` — Client Dimensions in Windowed Mode**: Asserts client dimensions adjust to 1280x720 windowed resolution.
25. **`T1-F5-05` — Cursor Remains Hidden After Toggle**: Asserts cursor remains hidden and clip rect updates to windowed bounds.

#### Feature F6: Alt+Enter Windowed to Fullscreen/Borderless Mode (5 Tests)
26. **`T1-F6-01` — Alt+Enter Keystroke in Windowed Mode**: Dispatches synthetic `VK_MENU` + `VK_RETURN` while in windowed mode.
27. **`T1-F6-02` — Style Transition to WS_POPUP**: Asserts window style changes from `WS_OVERLAPPEDWINDOW` to `WS_POPUP`.
28. **`T1-F6-03` — Removal of Title Bar and Borders**: Asserts title bar caption and window borders are removed.
29. **`T1-F6-04` — Expansion to Monitor Bounds**: Asserts window dimensions expand to full monitor resolution.
30. **`T1-F6-05` — Cursor Clip Rect Expanded and Hidden**: Asserts clip rect expands to monitor rect and cursor stays hidden.

#### Feature F7: Window Placement & Bounds Integrity (5 Tests)
31. **`T1-F7-01` — Window Placement Restoration**: Toggles borderless -> windowed -> borderless -> windowed and verifies `WINDOWPLACEMENT` rect restoration.
32. **`T1-F7-02` — No Off-Screen Placement**: Asserts window title bar top coordinate remains inside desktop work area.
33. **`T1-F7-03` — Aspect Ratio Preservation**: Asserts client rect maintains 16:9 ratio within 5% tolerance.
34. **`T1-F7-04` — No Coordinate Drift Over Repeated Toggles**: Asserts window position does not drift over repeated toggle cycles (delta <= 4px).
35. **`T1-F7-05` — Window Placement API Integrity**: Asserts `GetWindowPlacement` reports valid `SW_SHOWNORMAL` / `SW_SHOW`.

---

### Tier 2: Boundary & Corner Cases (5 Tests)
36. **`T2-BC-01` — Rapid Consecutive Alt+Enter Presses**: Sends 4 rapid Alt+Enter keystrokes at 50ms intervals; asserts no crash, deadlock, or oscillation.
37. **`T2-BC-02` — Alt Held With Other Keys (No Spurious Toggle)**: Dispatches `Alt+W`, `Alt+S`, and `Alt+Space`; asserts display mode does not change.
38. **`T2-BC-03` — Defocus During Active Polling**: Triggers abrupt focus loss during background polling loop; verifies clip release.
39. **`T2-BC-04` — Window Minimize and Restore**: Minimizes window (`SW_MINIMIZE`), verifies clip release; restores window (`SW_RESTORE`), verifies cursor re-hiding.
40. **`T2-BC-05` — Key Repeat Suppression on Alt+Enter**: Holds Alt+Enter continuously for 300ms; asserts toggle occurs exactly once without oscillation.

---

### Tier 3: Cross-Feature Interactions (5 Tests)
41. **`T3-CI-01` — Alt-Tab Followed Immediately by Alt+Enter**: Sends Alt-Tab followed by Alt+Enter; asserts toggle is ignored while window is unfocused.
42. **`T3-CI-02` — Mode Toggle Only When Game Focused**: Verifies display mode toggle is strictly gated on active window focus.
43. **`T3-CI-03` — Mouse Look Active During Mode Toggle**: Mode toggling with active mouse input updates cursor clipping smoothly without camera jump.
44. **`T3-CI-04` — Focus Loss During Mode Transition**: Abrupt focus loss mid-transition releases cursor clipping without hanging.
45. **`T3-CI-05` — Interleaved Mode Toggles and Focus Shifts**: Alternating mode toggles and focus changes maintain capture and display state integrity.

---

### Tier 4: Real-World Gameplay Scenarios (2 Tests)
46. **`T4-GP-01` — Complete End-to-End User Journey**: Full lifecycle simulation:
    - Step 1: Boot into borderless mode -> verify hidden cursor and popup style.
    - Step 2: Toggle Alt+Enter to windowed -> verify mode switch and hidden cursor.
    - Step 3: Alt-Tab out to desktop -> verify cursor visible and clip released.
    - Step 4: Refocus game -> verify cursor re-hidden and clip re-engaged.
    - Step 5: Toggle Alt+Enter back to borderless -> verify popup mode and hidden cursor.
47. **`T4-GP-02` — Windowed Gameplay Progression Lifecycle**:
    - Boot in windowed mode with `AA_AUTO_START=1`.
    - Verify hidden cursor across intro movies and mission select.
    - Defocus to desktop -> verify arrow visible and unclipped.
    - Refocus -> verify cursor re-hidden during active gameplay.

---

## 6. Coverage Thresholds & Quality Gates

To satisfy Milestone M3 verification and release criteria:
1. **Total Automated Tests**: 47 test cases.
2. **Required Pass Rate**: **100% (47 / 47 tests passed)**.
3. **Regression Tolerance**: 0 failed tests allowed.
4. **Report Verification**: Execution generates full Markdown report via `-ReportPath`.
