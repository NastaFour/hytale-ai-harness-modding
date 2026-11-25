---
name: hytale-data-assets-worldgen
description: "Trigger: data assets, content pack, items, blocks, recipes, loot tables, NPC roles, prefabs, worldgen, HytaleGenerator, SchemaGenerator, DefaultAssetMap, LoadedAssetsEvent. Author Hytale Common/ and Server/ data assets, WorldGen V2 node graphs, and runtime Java asset bindings."
license: MIT
allowed-tools: Read Write Edit Bash(pwsh:*) Bash(python:*)
metadata:
  trigger: ["data assets", "content pack", "items", "blocks", "recipes", "loot tables", "NPC", "worldgen", "HytaleGenerator", "SchemaGenerator"]
  scope: [project]
  version: "1.0.0"
---

# Hytale Data Assets, Content Packs & WorldGen V2

Use this skill when authoring JSON data assets under `Common/` and `Server/`, creating WorldGen V2 biomes/structures, or binding data assets to Java server plugins.

## Directory Taxonomy (`<pack-root>` or `src/main/resources/`)

Remember: Java plugins bundling `Common/` or `Server/` MUST declare `"IncludesAssetPack": true` in `manifest.json`. Matching paths override base game `Assets.zip` entries.

| Relative Path | Scope | Purpose & Verified Conventions |
| :--- | :--- | :--- |
| `manifest.json` | Metadata | PascalCase pack identity and dependencies |
| `Common/UI/Custom/` | Client | Declarative `.ui` layouts and UI textures |
| `Common/Blocks/` | Client | Custom block `.blockymodel` files and 32px-multiple textures |
| `Common/Characters/` | Client | Character/NPC `.blockymodel`, textures, `.blockyanim` folders |
| `Server/Item/Items/` | Server | Item JSONs (`AssetIconProperties`, `ItemEntityConfig`, weapons, portal keys) |
| `Server/Item/Block/` | Server | Functional block definitions and block components |
| `Server/Item/Recipes/` | Server | Crafting and processing recipes |
| `Server/Item/Interactions/` | Server | Combat, ability, and item-use trees (extract shared fragments used in 3+ places) |
| `Server/Drops/` | Server | Loot tables for blocks, chests, and bosses |
| `Server/NPC/Roles/` & `Spawn/` | Server | NPC AI behavior (`Variant`, `Reference`, health, skills) and zone spawn tables |
| `Server/Prefabs/` | Server | Prebuilt structures and dungeons for instances/worldgen |
| `Server/HytaleGenerator/` | Server (WorldGen V2) | Node Graph Assets (`Biomes/`, `WeightedMaterialProvider`, density functions, `WorldStructures/`) |
| `Server/PortalTypes/` | Server | Instance/dimension portal rules |
| `Server/Audio/` | Server | `SoundEvents` and `EQ/` configs for `AudioPlugin` |

## Official JSON Schemas & `Assets.zip` Inspection

Undocumented JSON keys (such as Block States or exact `HytaleGenerator` node properties) must be derived from official schemas or vanilla examples inside `%APPDATA%\Hytale\install\release\package\game\latest\Assets.zip` — never guessed:

1. Generate official JSON Schemas locally into `.hytale-harness\schemas\` via:
   ```powershell
   .\scripts\hytale.ps1 schemas
   ```
2. Inspect vanilla JSON examples inside `Assets.zip` (e.g. `Server/HytaleGenerator/Biomes/Examples/`) in read-only temp extractions before writing complex WorldGen V2 or NPC definitions.

## Runtime Java Asset Binding

1. **Read Native Asset Maps**: Query loaded definitions via `DefaultAssetMap` or `IndexedLookupTableAssetMap`:
   ```java
   Item item = Item.getAssetMap().getAsset(itemId);
   String key = item.getTranslationKey();
   ```
2. **React to Loads & Hot Reloads**: Subscribe to `LoadedAssetsEvent` filtered by asset class:
   ```java
   getEventRegistry().registerGlobal(LoadedAssetsEvent.class, Item.class, this::onItemLoad);
   ```
3. **Custom Data Asset Types**: Register a `HytaleAssetStore` in `JavaPlugin#setup()` (`getAssetRegistry().register(HytaleAssetStore.builder(MyAsset.class, new DefaultAssetMap<>())...)`) to gain automatic Asset Editor and `SchemaGenerator` integration. Listen to `GenerateSchemaEvent` to inject custom schema links.

## Curated Golden Reference Repositories

- `https://github.com/Zleub/Z_Cities` (WorldGen V2 ModJam 2026 city/structure generation)
- `https://github.com/DevSrSouza/SouzaSkygrid` (Java 25 custom world generator)
- `https://github.com/HyperSystemsDev/HytaleServerDocs` (WorldGen V2 density graph reference)
- `https://github.com/Ranork/Hytale-Server-Unpacked` (`HYTALE_CORE_API.md` reference)

## Verification

Run `.\scripts\hytale.ps1 verify -ProjectDir "<mod-dir>"` (and add `-ValidateWorldGen` when editing `Server/HytaleGenerator/`) to verify JSON syntax, schema compliance, and headless server asset validation.
