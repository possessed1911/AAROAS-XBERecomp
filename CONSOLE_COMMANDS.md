# America's Army: Rise of a Soldier — Console Commands

This document provides a comprehensive reference for the Unreal Engine 2 in-game developer and debug console in **America's Army: Rise of a Soldier (PC Recomp)**.

---

## Accessing the Console

- Press **`~` (Tilde / Grave Accent)** or **`F2`** to toggle the console window.
- Mouse capture is released while the console is open.
- Use **`Up Arrow`** and **`Down Arrow`** to navigate command history.
- Command history persists across game sessions in `console_history.txt`.
- Type **`clear`** or **`cls`** to clear the console output buffer.

---

## Built-In Engine & Recomp Commands

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `stat fps` | None | Toggles real-time FPS and frame time overlay on screen. |
| `stat all` | None | Toggles performance statistics overlay. |
| `stat none` | None | Disables all HUD statistics overlays. |
| `clear` / `cls` | None | Clears the console log window. |
| `exit` / `quit` | None | Immediately closes the game and exits to desktop. |
| `disconnect` | None | Disconnects from the current server or match and returns to menu. |
| `reconnect` | None | Reconnects to the last visited game server. |

---

## Tactical & Multiplayer Cheats (`mpcheat`)

*America's Army: Rise of a Soldier* exposes tactical debug routines through the `mpcheat` command dispatcher on the local player controller.

| Command | Parameters / Values | Description |
| :--- | :--- | :--- |
| `mpcheat god` | None | Toggles invulnerability (God mode) on/off. |
| `mpcheat enterghostmode` | None | Enables ghost mode (noclip flight through walls and terrain). |
| `mpcheat walk` | None | Disables ghost/fly mode and restores normal gravity/walking physics. |
| `mpcheat changeclass` | `<class>` | Changes active soldier class loadout mid-mission.<br>Classes: `r` (Rifleman), `g` (Grenadier), `ar` (Automatic Rifleman), `s` (Sniper), `sf` (Special Forces). |
| `mpcheat slomo` | `<multiplier>` | Changes simulation speed multiplier (e.g. `mpcheat slomo 0.5` for slow-motion, `mpcheat slomo 1.0` for normal). |
| `mpcheat fov` | `<degrees>` | Sets the camera field of view in degrees (e.g. `mpcheat fov 90`, `mpcheat fov 105`). |
| `mpcheat behindview` | `0` or `1` | Toggles third-person camera perspective. |
| `mpcheat freecamera` | None | Toggles detached spectator free-camera mode. |
| `mpcheat nvg` | None | Toggles Night Vision Goggles. |
| `mpcheat binoc` | None | Toggles tactical binoculars overlay. |
| `mpcheat medic` | None | Calls field medic / restores soldier health and bandages wounds. |
| `mpcheat pause` | None | Pauses / unpauses the match simulation. |
| `mpcheat playerlock` | `0` or `1` | Locks/unlocks player pawn movement for testing animations or cinematic staging. |
| `mpcheat actorlist` | None | Dumps all active World actors to the log. |
| `mpcheat dactorlist` | None | Dumps dynamic actors to the log. |
| `mpcheat endgame` | None | Forces current round / mission to end immediately. |
| `mpcheat flood` | None | Network bandwidth and packet flooding stress test. |
| `mpcheat params` | None | Displays current match rules and scoring parameters. |

---

## Standard Unreal Engine 2 Cheats (`CheatManager`)

In single-player career missions and local test matches, standard UE2 CheatManager routines are also dispatched:

| Command | Parameters | Description |
| :--- | :--- | :--- |
| `god` | None | Toggles invulnerability. |
| `ghost` | None | Walk through walls and geometry. |
| `fly` | None | Flight mode with collision enabled. |
| `walk` | None | Restores standard walking physics. |
| `allweapons` | None | Grants all standard infantry weapons. |
| `killpawns` | None | Eliminates all AI bot pawns in the level. |
| `killall` | `<class>` | Destroys all spawned instances of specified Actor class. |
| `playersonly` | None | Freezes world simulation and AI while allowing the player to move. |
| `freezeframe` | `<seconds>` | Freezes execution for the specified duration. |
| `changesize` | `<scale>` | Scales the player collision cylinder and mesh size. |
| `teleport` | None | Teleports the player pawn to the crosshair surface. |
| `slomo` | `<multiplier>` | Sets game speed (e.g. `slomo 0.5` or `slomo 2.0`). |
| `summon` | `<class>` | Spawns an actor class at the player's crosshair. |
| `viewactor` | `<name>` | Directs camera to view a specific actor. |
| `viewbot` | None | Cycles camera perspective through active AI bots. |
| `viewplayer` | `<name>` | Directs camera to spectate another player by name. |
| `viewclass` | `<class>` | Views nearest actor of given class. |

---

## Camera, View & HUD Commands

| Command | Parameters | Description |
| :--- | :--- | :--- |
| `fov` | `<degrees>` | Sets horizontal camera field of view (e.g. `fov 90`). |
| `behindview` | `0` / `1` | `1` enables third-person camera; `0` returns to first-person. |
| `shoulderview` | None | Positions third-person camera over the shoulder. |
| `showhud` | None | Toggles HUD on/off (useful for clean screenshots). |
| `showobjectives` | None | Displays current mission objectives on screen. |
| `showdebug` | None | Toggles engine debug text overlay (pawn state, velocity, target). |
| `toggledebug` | None | Toggles verbose AI and combat state diagnostics. |

---

## Communication & Team Commands

| Command | Parameters | Description |
| :--- | :--- | :--- |
| `say` | `<message>` | Sends a global chat message to all players. |
| `teamsay` | `<message>` | Sends a tactical chat message to teammates only. |
| `suicide` | None | Kills the player pawn to respawn at next wave. |

---

## Level & Map Management

| Command | Parameters | Description |
| :--- | :--- | :--- |
| `open` | `<mapname>` | Loads a mission map directly (e.g. `open MP_Bridge`, `open MissionR4_Tunnel`). |
| `switchlevel` | `<mapname>` | Server-side seamless map transition. |
| `restartlevel` | None | Restarts the current mission or match from the beginning. |
| `endmission` | None | Ends the mission and proceeds to debriefing. |

---

## AI & Bot Debugging Commands

| Command | Parameters | Description |
| :--- | :--- | :--- |
| `addbot` | `[team]` | Spawns an AI bot into the game. |
| `botaccuracy` | `<0.0 - 1.0>` | Sets global AI shooting accuracy. |
| `botfollow` | None | Orders AI squad to follow player position. |
| `botdontattack` | `0` / `1` | Prevents AI bots from firing weapons. |
| `botreload` | None | Forces AI bots to perform a reload cycle. |
| `botteleport` | None | Teleports squad bots directly to the player. |
| `botsetinvulnerable` | `0` / `1` | Toggles invulnerability on AI squad members. |
