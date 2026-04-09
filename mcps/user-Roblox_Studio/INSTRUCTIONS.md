Studio MCP Proxy — bridges MCP clients with Roblox Studio.

## DataModel hierarchy / exploration

When the Cursor agent needs a **live Studio tree snapshot** (Workspace, ReplicatedStorage, etc.), the project rule **`.cursor/rules/Roblox-Studio-Explore-Subagent.mdc`** instructs it to invoke MCP tool **`subagent`** with **`subagent_type: "explore"`** and a concrete `task` (not for Rojo `src/` — use repo search tools for that).

## Repeatable full playtest (shop → loadout → arena pad)

The Studio MCP **`subagent`** tool only supports `subagent_type: "explore"`; it cannot run this workflow by type.

For a **repeatable, step-by-step automation** (navigation, E prompts, React shop clicks, loadout, blue pad, wait), use the project Cursor skill:

**`.cursor/skills/roblox-full-playtest-mcp/SKILL.md`** (`roblox-full-playtest-mcp`)

Enable or @-mention that skill in Cursor, then ask to run the playtest. The agent will call `user-Roblox_Studio` tools in order: `list_roblox_studios`, `start_stop_play`, `character_navigation`, `user_keyboard_input`, `user_mouse_input`, `search_game_tree` / `inspect_instance` for path discovery, `get_console_output`.
