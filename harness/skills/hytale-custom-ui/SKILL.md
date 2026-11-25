---
name: hytale-custom-ui
description: "Trigger: custom ui, .ui, HUD, CustomUIHud, InteractiveCustomUIPage, UICommandBuilder, UIEventBuilder, sendUpdate, WindowManager, BenchWindow. Author Hytale 2026 declarative .ui files under Common/UI/Custom/ and server-driven Java UI pages/windows."
license: MIT
allowed-tools: Read Write Edit Bash(pwsh:*) Bash(python:*)
metadata:
  trigger: ["custom ui", ".ui", "CustomUIHud", "InteractiveCustomUIPage", "UICommandBuilder", "UIEventBuilder", "sendUpdate", "BenchWindow"]
  scope: [project]
  version: "1.0.0"
---

# Hytale Custom UI (`.ui` DSL & Server-Driven Pages)

Use this skill when building HUD overlays, interactive menus, or container/machine screens in Hytale 2026.

## Core Rules

1. **Server-Driven Declarative Model**: The C# client renders `.ui` files downloaded from `src/main/resources/Common/UI/Custom/` (requires `"IncludesAssetPack": true` in `manifest.json`). The server cannot synthesize `.ui` files dynamically; it instantiates and mutates existing templates via `UICommandBuilder`.
2. **No Client Java GUI APIs**: Never use Minecraft `Screen`, `GuiGraphics`, or base-client menu overrides (main menu, hotbar, and standard inventory are fixed in C#).
3. **Always Call `sendUpdate()`**: Inside `InteractiveCustomUIPage#handleDataEvent(...)`, calling `sendUpdate()` after `update(false, delta)` is **mandatory**; omitting it leaves the client stuck on `"Loading..."`.
4. **UI Textures Exempt from 32px Rule**: Custom UI icons and 9-slice `PatchStyle` textures under `Common/UI/Custom/` do NOT need to be multiples of 32px.

## `.ui` DSL Reference

- Imports & variables: `$Common = "Common.ui";` (`$Common.@Variable`), `@PanelBg = PatchStyle(TexturePath: "MyBackground.png");` (paths relative to the `.ui` file).
- Selectors from Java: `#MyButton`, `#List[0]`, `#List[0] #Title`, `#TitleLabel.TextSpans`.
- Verified primitives: `Group`, `Label`, `TextField`, `ItemGrid` (supports `SlotsPerRow`/`SlotSize`; no `DefaultItemIcon` needed since Update 7), `ItemSlot`, `ItemSlotButton`, `ItemIcon`, `ItemPreviewComponent`, `ProgressBar`, `CircularProgressBar`, `TabNavigation`.

```text
$Common = "Common.ui";
@PanelBg = PatchStyle(TexturePath: "MyBackground.png");

Group {
    LayoutMode: Center;

    Group #MainPanel {
        Background: @PanelBg;
        Anchor: (Width: 640, Height: 480);
        LayoutMode: Top;

        Label #TitleLabel {
            Style: (FontSize: 32, Alignment: Center);
            Anchor: (Top: 24);
            Text: "Machine Controller";
            Padding: (Full: 10);
        }

        TextField #FilterInput {
            Style: $Common.@DefaultInputFieldStyle;
            Background: $Common.@InputBoxBackground;
            Anchor: (Top: 12, Width: 260, Height: 48);
            Padding: (Full: 10);
        }
    }
}
```

## Java Server-Side Lifecycle

- **Persistent HUDs**: Extend `CustomUIHud`, call `uiCommandBuilder.append("MyHud.ui")` in `build(UICommandBuilder)`, and attach via `player.getHudManager().setCustomHud(...)` (use `MultipleHUD` when coexisting with other HUD mods).
- **Non-Interactive Pages**: Extend `CustomUIPage`.
- **Interactive Pages**: Extend `InteractiveCustomUIPage<PageData>` using `BuilderCodec<PageData>`, `UICommandBuilder`, and `UIEventBuilder`:
  - Open with `player.getPageManager().openCustomPage(ref, store, new MyPage(playerRef))`.
  - Close with `player.getPageManager().setPage(ref, store, Page.None)`.
  - Always verify exact `CustomPageLifetime` / `CustomUIEventBindingType` imports via `.\scripts\hytale.ps1 javap -ClassName <FQCN>`.
- **Inventory & Machine Windows**: Use `WindowManager`, `ItemContainerWindow`, `MaterialContainerWindow`, and `BenchWindow` / `CraftingWindow` subclasses when backing UI with real server inventories.
- **Localization**: Query `Item.getAssetMap().getAsset(itemId).getTranslationKey()` and pass `Message.translation(key)` to `commands.set("#Label.Text", msg)`.

## Client Diagnostics

Enable **Diagnostic Mode** in the client (`Settings > General`) to surface detailed traces for:
- `"Failed to apply Custom UI HUD commands"` -> `.ui` syntax or property typo.
- `"Could not find document XXXXX for Custom UI Append command"` -> path mismatch vs `Common/UI/Custom/` or missing `"IncludesAssetPack": true`.

## Curated Golden Reference Repositories

- `https://github.com/Buuz135/AdminUI` (complete `.ui` + `InteractiveCustomUIPage` implementation)
- `https://github.com/underscore95/Hytale-Sandbox-Plugin` (`ui-pages` branch with `UICommandBuilder` & `UIEventBuilder`)
- `https://github.com/ninesliced/Hytale-BetterMap` (HUD coexistence with `MultipleHUD` and `/bm` menu)

## Verification

Run `.\scripts\hytale.ps1 verify -ProjectDir "<mod-dir>"` to confirm every `.ui` path passed to `append("...")` exists under `Common/UI/Custom/` and passes headless `--validate-assets`.
