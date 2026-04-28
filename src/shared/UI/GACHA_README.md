# Gacha System

A self-contained weapon skin gacha system for Roblox. Players spin a slot-machine reel to win weapon skins. The first spin is always free. Subsequent spins cost Robux via a Developer Product. Duplicate wins grant consolation credits.

---

## Files

| File | Location | Purpose |
|------|----------|---------|
| `GachaGUI.lua` | `src/shared/UI/` | Full-screen overlay, reel animation, result panel |
| `GachaGUIConfig.lua` | `src/shared/Modules/` | All layout, animation, and theme constants |
| `GachaConfig.lua` | `src/shared/Modules/` | Skin pool, rarities, pricing, first-roll guarantee |
| `GachaServiceClient.lua` | `src/shared/Services/` | ProximityPrompt wiring, remote event handling |
| `GachaServiceServer.lua` | `src/server/Services/GachaService/` | Server-authoritative roll logic, receipt handling |

---

## Dependencies

### What you must provide

The gacha system does not own these — you must have working versions in your project.

#### 1. `SkinsConfig` — `src/shared/Modules/SkinsConfig.lua`

Must expose:

```lua
SkinsConfig.getSkin(skinId: string) -> Skin | nil
```

Where `Skin` has at minimum:

```lua
{
    name: string,           -- display name shown on the result panel
    iconAssetId: number,    -- rbxassetid for the skin icon (0 if none)
    iconDecalName: string?, -- optional: name of a Decal under ReplicatedStorage.Imports.Decals
}
```

#### 2. `ShopEconomyClient` — `src/shared/Services/ShopEconomyClient.lua`

Must expose:

```lua
ShopEconomyClient.GetSnapshot() -> { freeSpinAvailable: boolean, ... }
ShopEconomyClient.Subscribe(callback: () -> ())
```

`freeSpinAvailable` should be `true` when the player has not yet used their free first spin.

#### 3. `EconomyServiceServer` — `src/server/Services/EconomyService/EconomyServiceServer.lua`

Must expose:

```lua
EconomyServiceServer.GetPlayerData(player) -> { hasUsedFirstRoll: boolean, ... }
EconomyServiceServer.OwnsSkin(player, skinId: string) -> boolean
EconomyServiceServer.AddSkin(player, skinId: string)
EconomyServiceServer.AddCredits(player, amount: number)
EconomyServiceServer.SetHasUsedFirstRoll(player)
```

#### 4. `CombatConfig` — `src/shared/Modules/CombatConfig.lua`

Must expose:

```lua
CombatConfig.REMOTE_FOLDER_NAME: string   -- name of the folder in ReplicatedStorage holding remotes
CombatConfig.REMOTES.GACHA_RESULT: string
CombatConfig.REMOTES.GACHA_FREE_SPIN: string
CombatConfig.REMOTES.ECONOMY_SYNC: string
```

#### 5. Workspace location for the ProximityPrompt

`GachaServiceClient` looks for a part at:

```
Workspace.Lobby.Gacha.GachaCounter
```

This can be a `BasePart` or a `Model` (uses `PrimaryPart` or first `BasePart` found). If your world layout differs, change `findGachaCounterPart()` in `GachaServiceClient.lua`.

---

## Configuration

### `GachaConfig.lua`

Edit this to set up your skin pool and pricing:

```lua
DEV_FREE_ROLLS = false          -- set true to make all rolls free (dev/testing only)
DEVELOPER_PRODUCT_ID = 0        -- your Roblox Developer Product ID for paid rolls
ROLL_ROBUX_PRICE = 75           -- display-only price shown on the roll button

FIRST_ROLL = {
    skinId = "YourSkinId",      -- skin guaranteed on first spin
    isFree = true,
}

DUPE_CONSOLATION_CREDITS = 300  -- credits awarded when a duplicate is rolled

RARITIES = {
    { name = "Common",    weight = 60, color = Color3.fromRGB(...) },
    { name = "Rare",      weight = 25, color = Color3.fromRGB(...) },
    { name = "Epic",      weight = 12, color = Color3.fromRGB(...) },
    { name = "Legendary", weight = 3,  color = Color3.fromRGB(...) },
}

POOL = {
    { skinId = "MySkin",   rarity = "Rare" },
    { skinId = "MySkin2",  rarity = "Epic" },
}
```

### `GachaGUIConfig.lua`

Edit `Config.Theme` to match your project's colour palette and fonts without touching any GUI code:

```lua
Config.Theme = {
    FontDisplay = Enum.Font.Michroma,
    FontBody    = Enum.Font.Jura,
    BgVoid      = Color3.fromRGB(6, 8, 22),
    Panel       = Color3.fromRGB(12, 18, 42),
    -- ... etc
}
```

Animation timing knobs (also in `GachaGUIConfig.lua`):

| Field | Default | Effect |
|-------|---------|--------|
| `SpinDuration` | `6.0` | Seconds the reel takes to decelerate to the winning cell |
| `SettleDuration` | `1.5` | Seconds to ease back from the overshoot position to the exact target |
| `SpinPower` | `3` | Exponent of the ease-out curve — higher brakes harder and earlier |
| `Overshoot` | `0.008` | Fraction past the target the reel travels before snapping back (0 = no bounce) |
| `LandPause` | `0.2` | Seconds between the reel settling and the selector glow starting |
| `ResultDelay` | `0.6` | Seconds between the selector glow starting and the result panel appearing |

---

## Startup wiring

### Client (`Client.client.lua`)

```lua
local GachaServiceClient = require(Shared.Services.GachaServiceClient)
GachaServiceClient.Init()
-- GachaServiceClient.Init() also requires and inits GachaGUI internally
```

### Server (`Server.server.lua`)

```lua
local GachaServiceServer = require(script.Parent.Services.GachaService.GachaServiceServer)
GachaServiceServer.Init()
```

---

## Result payload

When a roll completes the server fires `GACHA_RESULT` to the client with this payload, which is forwarded directly to `GachaGUI.ShowResult()`:

```lua
{
    skinId: string,               -- key into SkinsConfig
    skinName: string,             -- display name (resolved server-side from SkinsConfig)
    iconAssetId: number,          -- rbxassetid for icon (0 if none)
    rarity: string,               -- "Common" | "Rare" | "Epic" | "Legendary"
    duplicate: boolean,           -- true if player already owns this skin
    consolationCredits: number?,  -- only present when duplicate = true
    isFree: boolean,              -- true if this was the free first spin
}
```

If you want to react to roll results elsewhere on the client (e.g. to update an inventory panel), use:

```lua
GachaServiceClient.SubscribeResult(function(payload)
    -- payload has the same shape as above
end)
```
