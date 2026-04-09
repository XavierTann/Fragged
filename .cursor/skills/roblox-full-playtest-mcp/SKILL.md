---
name: roblox-full-playtest-mcp
description: >-
  Drives the full Fragged/Tanxyx solo playtest in Roblox Studio via the user-Roblox_Studio
  MCP: shop (buy Plasma Carbine), weapon storage loadout (equip primary), blue pad queue,
  wait for arena teleport. Use when the user asks to run the Studio playtest flow, full MCP
  shop-to-arena automation, repeatable Roblox MCP playtest, or "subagent" / one-click playtest.
---

# Roblox full playtest (Studio MCP)

## Limitation

The **Roblox Studio MCP `subagent` tool** only accepts `subagent_type: "explore"`. There is no custom MCP subagent slot. This skill is the repeatable substitute: follow it **exactly** whenever the user wants the automated flow.

## Preconditions

- **Roblox Studio** open with the correct place; MCP connected (`list_roblox_studios`).
- **Game not playing yet**, or stop first (`start_stop_play` with `is_start: false`) then start clean.
- Solo queue: `LobbyConfig.MIN_PLAYERS = 1` (already set in this repo for dev).
- **Credits**: `CreditsConfig.GRANT_TEST_CREDITS` grants shop credits in Studio; DataStore may still warn if API access is disabled.

## Tool server

Always use MCP server **`user-Roblox_Studio`**. Read each tool’s schema under `mcps/user-Roblox_Studio/tools/` before calling if parameters are unclear.

## Phase A — Boot

1. **`list_roblox_studios`** — confirm the active studio is the right project; use **`set_active_studio`** if needed.
2. **`start_stop_play`** with `{"is_start": true}`.

## Phase B — Resolve player name (required for debugging only)

Run **`search_game_tree`** with `path: "Players"`, `max_depth: 2`, `head_limit: 20`. Note the solo test `Player` child name (e.g. `CoreRekt`). **GUI clicks** must use **`LocalPlayer.PlayerGui...`** in `instance_path` (not the literal username).

## Phase C — Resolve fragile React shop paths (do this every run if unsure)

Shop rows are **React-Roblox** instances with **numeric names**; paths can shift between edits.

1. **`search_game_tree`**: `path` = `Players.<YourPlayer>.PlayerGui.ShopReactGUI`, `instance_type`: `TextButton`, `max_depth`: 10, `head_limit`: 50.
2. **`inspect_instance`** on each `TextButton` whose `Text` is **`BUY`**. **Plasma Carbine** is usually the **first catalog row**; its button often has a **magenta / pink** `BackgroundColor3` (high R, lower G, high B). Pick that path as **`PLASMA_BUY_PATH`**.
3. Find **close** `TextButton` with **`Text`** = **`X`** under the same `ShopReactGUI` tree — set **`SHOP_CLOSE_PATH`**.

If inspection is inconclusive, open the shop once (Phase D step 1–2 only), repeat search/inspect.

## Phase D — Executed sequence (copy argument shapes)

Use **`character_navigation`** with `instance_path` starting with `game.Workspace...` (per MCP schema).

| Order | Tool | Summary |
|------:|------|--------|
| 1 | `character_navigation` | `{"instance_path": "game.Workspace.GunShop.ShopKeeper", "speed_multiplier": 2}` |
| 2 | `user_keyboard_input` | `{"actions": [{"action": "wait", "wait_time_ms": 500}, {"action": "keyPress", "key_code": "E"}]}` |
| 3 | `user_mouse_input` | After **wait ~700ms**, **`moveTo`** `instance_path`: **`LocalPlayer.PlayerGui.` + PLASMA_BUY_PATH**, then **`mouseButtonClick`** `left` |
| 4 | `user_mouse_input` | After **wait ~400ms**, **`moveTo`** `LocalPlayer.PlayerGui.` + SHOP_CLOSE_PATH, **click** |
| 5 | `character_navigation` | `{"instance_path": "game.Workspace.GunShop.WeaponStorage", "speed_multiplier": 2}` |
| 6 | `user_keyboard_input` | `wait` 500ms → **E** |
| 7 | `user_mouse_input` | `wait` 600ms → **`moveTo`** `LocalPlayer.PlayerGui.LoadoutGUI.Overlay.Modal.PrimaryWeapons.PlasmaCarbine` → **click** → `wait` 250ms → **`moveTo`** `LocalPlayer.PlayerGui.LoadoutGUI.Overlay.Modal.DetailPanel.EquipBtn` → **click** |
| 8 | `user_mouse_input` | `wait` 400ms → **`moveTo`** `LocalPlayer.PlayerGui.LoadoutGUI.Overlay.Modal.CloseBtn` → **click** |
| 9 | `character_navigation` | `{"instance_path": "game.Workspace.Lobby.SpawnPads.BluePad", "speed_multiplier": 2}` |
|10 | `user_keyboard_input` | `{"actions": [{"action": "wait", "wait_time_ms": 10000}]}` |

**Typical defaults** (when React tree matches prior successful runs):

- `PLASMA_BUY_PATH` = `ShopReactGUI.Frame.2.4.2.3.8`
- `SHOP_CLOSE_PATH` = `ShopReactGUI.Frame.2.3.3`

These **must** be verified after UI refactors.

## Phase E — Verify + report

1. **`search_game_tree`**: `Workspace`, keywords matching the **player character** model name, `max_depth` 2 — confirm **`PlasmaCarbine`** `Tool` under **`Workspace.{CharacterName}`** or in **Backpack**.
2. **`get_console_output`** — summarize **DataStore** / **Save failed** / **GetConnectedParts** warnings for the user.
3. Ask whether to **`start_stop_play`** `is_start: false` (stop session).

## Failure recovery

- **Shop did not open**: increase waits after **E**; **`inspect_instance`** on `Workspace.GunShop.ShopKeeper` for **`ProximityPrompt`** / **`HumanoidRootPart`**; move closer with **`character_navigation`**.
- **BUY mis-clicked**: re-run Phase C; ensure **`ShopReactGUI.Enabled`** is true before clicks (optional **`inspect_instance`** on `Players.*.PlayerGui.ShopReactGUI`).
- **`PlasmaCarbine` missing from loadout list**: purchase failed or not owned — repeat shop phase; check economy **`execute_luau`** only if MCP allows single-line scripts.

## What to return to the user

Short summary: paths used, whether **PlasmaCarbine** appeared on character, console issues, and whether the session is still playing.
