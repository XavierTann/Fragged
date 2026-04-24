---
description: 
alwaysApply: true
---

You are working in a Roblox project that follows a strict Rojo-based source layout. Use the existing folder structure and file naming as architectural guidance only. Treat the current files as examples and templates for placement, naming, and organization. Do not assume every existing service, module, or UI file must be imported, referenced, modified, or depended on unless the task explicitly requires it.

PROJECT ARCHITECTURE OVERVIEW

This project is split into three main runtime areas under src:

- src/client
- src/server
- src/shared

The project uses explicit startup entrypoints:

- src/client/Client.client.lua
- src/server/Server.server.lua

These two files are the root boot scripts.

STARTUP AND SERVICE PATTERN

This codebase uses a consistent startup pattern for both client and server:

1. Each runtime service should be implemented as a ModuleScript that returns a table.
2. That returned table contains the service's public functions and an `Init` function.
3. The startup script is responsible for requiring each service module and calling its `Init` function.
4. Services should not rely on implicit startup or automatic discovery unless explicitly implemented.
5. Prefer explicit initialization through the root startup scripts.

Use this as the model for both client and server:

Client startup pattern:
- require the service module
- call `Service:Init()` or `Service.Init()` depending on the module's chosen method style
- print or log startup completion only in the startup script if needed

Example pattern:
- `Client.client.lua` requires client service modules from the correct folder
- each client service module returns a table
- `Client.client.lua` calls each module's `Init`

Server startup pattern:
- `Server.server.lua` requires server service modules
- each server service module returns a table
- `Server.server.lua` calls each module's `Init`

SERVICE MODULE REQUIREMENTS

When generating service modules, follow these rules:

1. Service modules must return a table.
2. The table should expose all public methods for that service.
3. The table must include an `Init` function for startup wiring.
4. Event connections, remote bindings, listeners, and one-time setup should generally happen inside `Init`.
5. Helper functions that are meant to be private can be local functions or private methods on the service table.
6. Do not create service scripts that execute all startup logic immediately on require unless explicitly requested.
7. Startup should remain controlled by the root boot script.

METHOD STYLE

Use a consistent method style inside each module.

Allowed styles:
- colon methods, such as `function Service:Init()`
- dot methods, such as `function Service.Init()`

If a module uses colon methods:
- initialize it with `Service:Init()`

If a module uses dot methods:
- initialize it with `Service.Init()`

Prefer matching the style already used by the surrounding code in that service.

RETURN STYLE

Preferred returned-module shape:

- a service table containing public functions
- an `Init` function on that same table
- return the table itself

This is the target pattern:

- create a table like `local CombatService = {}`
- define methods on it
- return that table, or return an equivalent table/metatable-based service object if that pattern is already intentionally used

Do not generate modules that return a bare function when the code is meant to be a service.

BOOTSTRAP RULES

1. Client.client.lua is the single client startup script.
   - It is responsible for initializing client-side systems that need startup wiring.
   - New client systems should generally be required and started from here, either directly or through a clear initialization flow.
   - Do not create extra startup scripts unless explicitly requested.

2. Server.server.lua is the single server startup script.
   - It is responsible for initializing server-side systems that need startup wiring.
   - New server systems should generally be required and started from here, either directly or through a clear initialization flow.
   - Do not create competing server boot flows.

3. Existing services and modules are examples of project conventions.
   - They are templates for structure and naming.
   - Do not automatically depend on them.
   - Do not assume new code must call into them.
   - Only reference an existing service if the feature being implemented actually belongs to that service or clearly integrates with it.

4. If adding a new service or runtime system:
   - Client-side initialization should be wired into Client.client.lua when startup registration is needed
   - Server-side initialization should be wired into Server.server.lua when startup registration is needed

FOLDER STRUCTURE

Treat this tree as the canonical layout pattern:

src/
  client/
    Client.client.lua
    UI.client.lua

  server/
    Services/
      AbilityService/
        AbilityServiceServer.lua
      CombatService/
        CombatServiceServer.lua
      GameFlowService/
        GameFlowServiceServer.lua
      NotifyService/
        NotifyServiceServer.lua
      ShopService/
        ShopServiceServer.lua
    Server.server.lua

  shared/
    Classes/
      CombatService/
        ChaosBall.lua
        HomingBall.lua
        ParryPulse.lua
        PhaseStep.lua
        training_dojo.rbxm

    Modules/
      AbilitiesConfig.lua
      CoinsUtils.lua
      CooldownUtils.lua
      ModelUtils.lua
      RemoteEventUtils.lua
      TargetingUtils.lua
      TeleportUtils.lua
      ZoneTrackerUtils.lua

    Services/
      AbilityServiceClient.lua
      InputServiceClient.luau
      ShopServiceClient.lua

    UI/
      AbilityGUI.lua
      AbilityUIStore.lua
      MountUI.lua
      NotifyToast.lua
      RootUI.lua
      ShopGUI.lua
      ShopUIStore.lua
      root.story.lua

ROOT-LEVEL FILES

At the repository root there are also:
- .gitignore
- README.md
- aftman.toml

HOW TO INTERPRET EXISTING FILES

The existing files show:
- where similar code should live
- how features are grouped
- how services are named
- how shared modules are separated from runtime services
- how UI code is organized

They do not imply:
- that all new features must reuse those exact services
- that code should import existing modules by default
- that every new mechanic belongs in AbilityService or CombatService
- that every UI change must edit existing GUI files unless the request actually concerns those files

Use the structure as a template, not as a hard dependency graph.

GENERAL ORGANIZATION RULES

1. CLIENT CODE
   Put client runtime logic under src/client or src/shared/Services when it is a client service module meant to be initialized by the client bootstrap.

   Existing client-related files are examples of client-side placement patterns:
   - src/client/Client.client.lua
   - src/client/UI.client.lua
   - src/shared/Services/AbilityServiceClient.lua
   - src/shared/Services/InputServiceClient.luau
   - src/shared/Services/ShopServiceClient.lua

   Interpretation:
   - Client.client.lua is the client entrypoint
   - UI.client.lua is a client script related to UI startup or orchestration
   - src/shared/Services contains client-facing or shared runtime service modules when that pattern makes sense

   When adding client systems, prefer module-based services that are required from the client bootstrap rather than standalone scripts scattered throughout the tree.

2. SERVER CODE
   Major server runtime logic belongs under:
   - src/server/Services/<ServiceName>/

   Existing service folders are templates for folder-per-service organization, for example:
   - AbilityService/AbilityServiceServer.lua
   - CombatService/CombatServiceServer.lua
   - GameFlowService/GameFlowServiceServer.lua
   - NotifyService/NotifyServiceServer.lua
   - ShopService/ShopServiceServer.lua

   Follow this convention for new services when a new service is appropriate:
   - Create a folder named after the service
   - Place the main implementation in a file named <ServiceName>Server.lua

   Do not assume a new feature must be placed into an existing service unless it is actually part of that service's responsibility.

3. SHARED CODE
   Shared code belongs under src/shared and is divided by responsibility:

   A. src/shared/Classes
   - Contains class-like gameplay objects and domain-specific implementations
   - Existing example: src/shared/Classes/CombatService/
   - Use the domain-folder idea as a template
   - Do not assume all new classes belong under CombatService

   B. src/shared/Modules
   - Contains stateless helpers, configs, utility modules, and cross-cutting support code
   - Utility modules should live here when they are not runtime services
   - Naming convention currently favors descriptive utility names ending in Utils when appropriate

   C. src/shared/Services
   - Contains service modules intended for runtime use on the client side, and potentially shared service abstractions
   - Existing files here are examples of service module placement and naming
   - New modules only belong here if they truly fit that role

   D. src/shared/UI
   - Contains UI components, UI stores/state modules, mounting logic, and stories
   - Keep UI-related state, composition, and rendering here
   - New screens, widgets, stores, and mount/root helpers should generally live here when they are UI concerns

NAMING CONVENTIONS

Follow the current naming style consistently.

1. Server service files:
   - <ServiceName>Server.lua

2. Client service files:
   - <ServiceName>Client.lua
   - or .luau when appropriate if already used by surrounding code

3. Utility/config modules:
   - <Name>Utils.lua
   - <Name>Config.lua

4. UI files:
   - <Feature>GUI.lua
   - <Feature>GUIConfig.lua (layout config, lives in src/shared/Modules)
   - <Feature>UIStore.lua
   - RootUI.lua
   - MountUI.lua

5. Keep names explicit and domain-oriented.
   Prefer:
   - InventoryServiceServer.lua
   - InventoryServiceClient.lua
   - InventoryUtils.lua
   Avoid vague names like:
   - main.lua
   - helper.lua
   - thing.lua
   - manager.lua
   unless those names are already established by the project

IMPLEMENTATION EXPECTATIONS

When generating code for this codebase:

1. Respect the bootstrap architecture
   - Wire initialization through Client.client.lua or Server.server.lua when startup registration is needed
   - Do not assume automatic discovery unless explicitly implemented

2. Respect the explicit service-init pattern
   - Service modules should return a table
   - That table should expose its public API
   - That table should include `Init`
   - Startup scripts should require services and call `Init`

3. Respect domain boundaries
   - Server authority logic goes in src/server/Services
   - Shared logic and helpers go in src/shared
   - UI logic goes in src/shared/UI or existing client UI entrypoints
   - Avoid placing server-only code in shared

4. Keep modules focused
   - Services should encapsulate a clear responsibility
   - Utility modules should remain reusable and not act like hidden runtime boot scripts
   - UI stores should only hold UI-related state and behavior

5. Match existing file placement patterns before suggesting new files
   - Use nearby files as a placement reference
   - Reuse folder conventions
   - Do not force new code into an existing service just because that service exists

6. Prefer extending the existing architecture instead of introducing parallel architecture
   - Do not create a second unrelated bootstrap system
   - Do not create a second UI root if RootUI/MountUI already cover that concern
   - Do not create alternative startup entrypoints

HOW TO ADD NEW FEATURES

Use these rules when deciding placement:

1. New server gameplay feature
   - Put server runtime logic in src/server/Services/<FeatureService>/ if the feature deserves its own service
   - Main module file should be <FeatureService>Server.lua
   - The service should return a table with its functions and `Init`
   - Initialize it from Server.server.lua when startup wiring is required
   - If the feature clearly belongs to an existing service, it may be added there
   - Otherwise, create a new service rather than forcing it into an unrelated existing one

2. New client gameplay feature
   - Put client runtime module in src/shared/Services/<FeatureService>Client.lua if it behaves like a client service
   - Or place strictly local startup/orchestration logic under src/client if needed
   - The service should return a table with its functions and `Init`
   - Initialize it from Client.client.lua when startup wiring is required
   - Do not automatically attach it to AbilityServiceClient or ShopServiceClient unless that is the correct integration point

3. New shared gameplay class
   - Put under src/shared/Classes/<RelevantDomain>/
   - Group by feature or domain instead of dumping all classes into one folder
   - Use CombatService as an example of domain grouping, not as a mandatory location

4. New utility or config
   - Put under src/shared/Modules

5. New UI screen/component/store
   - Put under src/shared/UI
   - Root-level composition should work through RootUI and MountUI unless explicitly changed
   - Do not assume every UI change must modify AbilityGUI or ShopGUI unless the requested feature relates to them

ASSUMPTIONS TO MAKE

When assisting in this repository, assume the following unless told otherwise:

- Client.client.lua is the main client bootstrapper
- Server.server.lua is the main server bootstrapper
- Startup is explicit, not magical
- Services are module tables with `Init`
- Root startup scripts initialize services by calling `Init`
- Folder placement matters and should be preserved
- Existing files are examples of conventions, not mandatory dependencies
- New code should mirror the style and organization of adjacent files
- If a feature does not naturally belong to an existing service, create a new appropriately named module or service following the same conventions

UI SIZING AND POSITIONING RULES

All UI code must use Scale-based UDim2 values (UDim2.fromScale) for Size and Position. Do not use Offset-based UDim2 values (UDim2.fromOffset or pixel offsets in UDim2.new) for layout. This ensures the UI scales correctly across different screen sizes and devices (desktop, tablet, mobile).

Allowed uses of pixel/offset values:
- UICorner.CornerRadius (UDim with offset is acceptable for corner rounding)
- UIStroke.Thickness (inherently pixel-based)
- ScrollBarThickness (inherently pixel-based)

All text elements must use TextScaled = true so text scales with its container. Do not set TextSize on any TextLabel or TextButton. Remove UITextSizeConstraint unless explicitly requested.

For arranging repeating elements (weapon grids, icon rows, skin lists), prefer UIListLayout or UIGridLayout with Scale-based padding, combined with UIAspectRatioConstraint on children that need to maintain a fixed aspect ratio (e.g. square icons).

When converting a pixel value to scale, compute the fraction relative to the parent container's reference dimensions. For example, 16px padding in a 480px-wide parent becomes 0.033 scale.

UI LAYOUT CONFIG FILES

Every GUI script must have a companion layout config file that contains all hardcoded positioning and sizing constants. This makes it easy to tweak the UI without reading through the full GUI implementation.

Naming convention:
- GUI script: <Feature>GUI.lua (lives in src/shared/UI)
- Config file: <Feature>GUIConfig.lua (lives in src/shared/Modules)

Examples:
- GachaGUI.lua → GachaGUIConfig.lua
- LoadoutGUI.lua → LoadoutGUIConfig.lua
- ShopGUI.lua → ShopGUIConfig.lua

What goes in the config file:
- Modal size (width, height)
- All element sizes (width, height as scale fractions)
- All element positions (posX, posY as scale fractions)
- Corner radii
- Layout padding values
- Row heights, column widths, gaps
- Pixel-based constants that drive animation (e.g. reel cell size)
- Any other numeric layout value that would otherwise be a magic number in the GUI script

How to structure the config:
- Return a single table with nested sub-tables grouped by UI area (e.g. Config.Modal, Config.Title, Config.CloseBtn, Config.DetailPanel)
- Use clear, descriptive field names (Width, Height, PosX, PosY, CornerRadius, etc.)
- Computed/derived values (e.g. a Y position that depends on another element's bottom edge) should be calculated in the config file itself
- The GUI script requires the config and reads values from it instead of using inline numbers

What stays in the GUI script:
- Instance creation and parenting
- Theme colors and fonts (from ShopTheme)
- Event wiring and callbacks
- Runtime state and logic

When creating a new GUI:
1. Create the config file first with all layout constants
2. Build the GUI script referencing config values from the start
3. Never hardcode layout numbers directly in the GUI script

WHAT NOT TO DO

Do not:
- create extra boot scripts without a request
- place server code in client folders
- place client-only UI code in server folders
- invent a new top-level architecture
- flatten the Services folder structure
- rename existing files just to match personal preference
- move core modules unless explicitly instructed
- create generic folders like misc, temp, commonstuff, or helpers when a proper domain folder exists
- assume existing services must be imported or referenced in generated code
- force unrelated features into AbilityService, CombatService, ShopService, or any other current service just because those services already exist
- put startup side effects directly at module top level when they belong in `Init`
- use Offset-based UDim2 values for UI Size or Position (use Scale instead so UI scales across devices)

PREFERRED RESPONSE STYLE FOR CODE CHANGES

When suggesting changes:
1. First identify the correct file or folder based on this structure
2. Reuse existing naming conventions
3. Explain where new code belongs in terms of this architecture
4. Mention startup wiring in Client.client.lua or Server.server.lua only when relevant
5. Treat existing services as reference implementations unless the task explicitly calls for integration with them
6. Prefer service modules that return a table with functions plus `Init`

SUMMARY

This codebase uses a centralized bootstrap model:
- Client startup begins in Client.client.lua
- Server startup begins in Server.server.lua

Both startup scripts explicitly require service modules and call their `Init` functions.
Server logic is service-oriented and grouped under src/server/Services.
Shared code is separated into Classes, Modules, Services, and UI.
Existing files are structural examples and naming templates, not automatic dependencies.
All generated code should preserve this structure and extend it consistently without assuming every current service must be used.
