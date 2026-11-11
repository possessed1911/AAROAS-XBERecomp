# Milestone M1 Test Readiness: E2E Test Suite Creation

**Status**: READY FOR IMPLEMENTATION (Milestone M2 Hand-off)  
**Date**: 2026-11-11  
**Milestone**: M1 (E2E Test Suite Creation)  
**Author**: teamwork_test_writer (gen1 replacement)

---

## 1. Test Runner Command

The automated test suite is fully implemented, verified, and ready to execute against build artifacts in `out/build/release`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1
```

### Optional Test Flags & Invocations
- **List All Tests**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -ListTests
  ```
- **Run Specific Tier**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -Tier "1"
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -Tier "2"
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -Tier "3"
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -Tier "4"
  ```
- **Run Specific Feature (Tier 1)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -Tier "1" -Feature "F1"
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -Tier "1" -Feature "F5"
  ```
- **Generate Markdown Execution Report**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\test_e2e_cursor_display.ps1 -ReportPath "out/e2e_report.md"
  ```

---

## 2. Test Coverage Summary by Tier

| Tier | Category | Test IDs | Test Count | Status |
|---|---|---|:---:|:---:|
| **Tier 1** | Feature Coverage (F1 through F7) | `T1-F1-01` to `T1-F7-05` | 35 | READY |
| **Tier 2** | Boundary & Corner Cases | `T2-BC-01` to `T2-BC-05` | 5 | READY |
| **Tier 3** | Cross-Feature Interactions | `T3-CI-01` to `T3-CI-05` | 5 | READY |
| **Tier 4** | Real-World Gameplay Lifecycles | `T4-GP-01`, `T4-GP-02` | 2 | READY |
| **Total** | **All Verification Tiers** | | **47** | **READY** |

---

## 3. Feature Coverage Checklist

| Feature ID | Feature Name | Requirement Source | Automated Tests Assigned | Verification Method | Status |
|---|---|---|---|---|:---:|
| **F1** | Cursor Hidden in Borderless/Fullscreen | ORIGINAL_REQUEST R1 | `T1-F1-01` .. `T1-F1-05`, `T4-GP-01` | Win32 `GetCursorInfo`, `GWL_STYLE`, `GetClipCursor` | READY |
| **F2** | Cursor Hidden in Windowed Mode | ORIGINAL_REQUEST R1 | `T1-F2-01` .. `T1-F2-05`, `T4-GP-02` | Win32 `GetCursorInfo`, `WS_OVERLAPPEDWINDOW`, `ClipCursor` | READY |
| **F3** | Cursor Visible and Free on Defocus | ORIGINAL_REQUEST R1 | `T1-F3-01` .. `T1-F3-05`, `T2-BC-03`, `T4-GP-01` | Win32 `DefocusWindow`, `GetForegroundWindow`, unclip | READY |
| **F4** | Cursor Re-hidden on Window Refocus | ORIGINAL_REQUEST R1 | `T1-F4-01` .. `T1-F4-05`, `T2-BC-04`, `T4-GP-01` | Win32 `SetForegroundWindow`, cursor re-hidden | READY |
| **F5** | Alt+Enter Fullscreen to Windowed Mode | ORIGINAL_REQUEST R2 | `T1-F5-01` .. `T1-F5-05`, `T2-BC-01`, `T4-GP-01` | Win32 `keybd_event` Alt+Enter, style switch to `WS_OVERLAPPEDWINDOW` | READY |
| **F6** | Alt+Enter Windowed to Fullscreen Mode | ORIGINAL_REQUEST R2 | `T1-F6-01` .. `T1-F6-05`, `T2-BC-05`, `T4-GP-01` | Win32 `keybd_event` Alt+Enter, style switch to `WS_POPUP` | READY |
| **F7** | Window Placement & Bounds Integrity | PROJECT.md F7 / Caveats | `T1-F7-01` .. `T1-F7-05` | Win32 `GetWindowPlacement`, aspect ratio 16:9 check | READY |
| **F8** | Release Prohibition & Demo Integrity | ORIGINAL_REQUEST R3 | Audit gate | Operational restraint: No git push, no GitHub release | READY |

---

## 4. Milestone M2 Implementation Interface Contracts

The implementation team (Milestone M2) must satisfy the following interface contracts validated by this test suite:

1. **`app::WndProc` ↔ `ImGui` (`sdk/runtime/app/main.cpp`)**:
   - Set `io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;` so ImGui does not hijack `WM_SETCURSOR` and force `IDC_ARROW` during gameplay.
   - Initialize window class `wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);`.

2. **`app::WndProc` ↔ `OnMessage` (`src/common/game_info.cpp`)**:
   - Intercept `WM_SETCURSOR`: When `CanCaptureLocked(true, IsAltDown())` is true, call `SetCursor(nullptr)`, set `*result = TRUE`, and return `true`. When inactive, set `IDC_ARROW`.
   - Intercept `WM_SYSKEYDOWN`: When `wp == VK_RETURN && ((lp & (1 << 29)) != 0 || IsAltDown())`, toggle `app::Get().display_mode` between `Borderless` and `Windowed`, invoke `app::ApplyDisplay()`, persist via `app::Save()`, set `*result = 0`, and return `true`.

3. **Window Placement Restoration (`sdk/runtime/app/main.cpp`)**:
   - In `app::ApplyNow()`, preserve `g_window_placement` before switching to borderless, and restore via `SetWindowPlacement` when transitioning back to windowed mode.
