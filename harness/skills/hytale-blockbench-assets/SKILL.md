---
name: hytale-blockbench-assets
description: "Trigger: blockbench, blockymodel, blockyanim, 3D model, texture, UV, texel, bones, RandomAttachmentSets, AudioPlugin, SoundEvents. Enforce Hytale 2026 Blockbench modeling, 32px-multiple texture density, animation taxonomy, and audio conventions."
license: MIT
allowed-tools: Read Write Edit Bash(pwsh:*) Bash(python:*)
metadata:
  trigger: ["blockbench", "blockymodel", "blockyanim", "3D model", "texel", "RandomAttachmentSets", "SoundEvents"]
  scope: [project]
  version: "1.0.0"
---

# Hytale Blockbench, 3D Models (`.blockymodel`), Animations & Audio

Use this skill when creating, inspecting, or validating 3D models, textures, `.blockyanim` animations, character attachments, or `SoundEvents`.

## Hard Geometry & Texture Constraints

Hytale retired Hytale Model Maker in favor of **Blockbench** with the official **`JannisX11/hytale-blockbench-plugin`**:

1. **Primitives Only**: `.blockymodel` supports **exclusively cubes (6 faces) and quads (2 faces)**. Spheres, pyramids, arbitrary triangles, and edge loops are forbidden.
2. **32px Texture Multiples**: 3D asset textures under `Common/Blocks/`, `Common/Characters/`, `Common/Items/`, and `Common/NPC/` MUST have width and height in **multiples of 32px** (`32`, `64`, `96`, `128`, ...); non-square ratios are allowed if both axes are multiples of 32.
3. **Texel-Locked Density & Scaling**: Target `64px/unit` for characters/attachments and `32px/unit` for blocks/props; keep stretch factors within `0.7x-1.3x`. Never scale geometry in-model to resize in-world — configure scale in server JSON definitions (`Item#scale` or NPC model definition).
4. **No PBR Workflows**: Hytale uses zero roughness, normal, or displacement maps (`_n.png`, `_s.png`). Hand-paint shading and ambient occlusion onto the albedo texture, avoiding pure white (`#FFFFFF`) and pure black (`#000000`).

## Bones, Attachments & `.blockyanim` Taxonomy

- **Standard Bone Hierarchy**: Preserve engine bone names (`root`, `hand-right`, etc.) on characters and creatures so automatic animations bind properly.
- **Attachments**: Configure fixed or probabilistic equipment/cosmetic layers via `RandomAttachmentSets` (two-level map: slot e.g. `"Hair"` / `"Armor"` -> weighted variants) and swap at runtime via `ActionModelAttachment`.
- **Standard NPC `.blockyanim` Subfolders**:
  - `Default/`: `Idle.blockyanim`, `Walk.blockyanim`, `Walk_Backward.blockyanim`, `Run.blockyanim`, `Jump.blockyanim`, `Fall.blockyanim`, `Crouch.blockyanim`, `Crouch_Walk.blockyanim`, `Alerted.blockyanim`, `Spawn.blockyanim`, `Sleep.blockyanim`, `Laydown.blockyanim`, `Wake.blockyanim`
  - `Damage/`: `Hurt.blockyanim`, `Death.blockyanim`, `Hurt_Fly.blockyanim`, `Death_Fly.blockyanim`
  - `Swim/`: `Swim_Idle.blockyanim`, `Swim.blockyanim`
  - `Fly/`: `Fly_Idle.blockyanim`, `Fly.blockyanim`
  - `Flavor/`: `Roar.blockyanim`, `Eat.blockyanim`
- **Audio**: `com.hypixel.hytale.builtin.audio.AudioPlugin` loads `SoundEvents` and `EQ/` configs from `Server/Audio/` (e.g. `Server/Audio/EQ/EQ_Default.json`). Keyframe-level sound bindings inside `.blockyanim` are `[Community/Unverified]`; inspect vanilla `.blockyanim` files in `Assets.zip` before authoring.

## `[Community/Unverified]` Safeguard for Programmatic `.blockymodel` / `.blockyanim`

No official public JSON Schema documents all internal keys of `.blockymodel` and `.blockyanim`. Follow these three safeguards:

1. **Derive Structure from `Assets.zip`**: Before editing or generating `.blockymodel` / `.blockyanim` JSON via script, inspect an analogous vanilla file from `%APPDATA%\Hytale\install\release\package\game\latest\Assets.zip`.
2. **Enforce Offline Linting**: Validate all 3D PNGs are multiples of 32px and ensure `Server/Item/` and `Server/NPC/` references point to valid `Common/` paths.
3. **Delegate Complex Rigs**: Limit custom scripts to validation, merging (`blockymodel-merger`), or trivial cubic props; author rigged/animated models in Blockbench using `JannisX11/hytale-blockbench-plugin`, `Hytale-Blockbench-Bridge`, or `blockbench-mcp-plugin` (`hytale://pieces/...`).

## Curated Golden Reference Repositories

- `https://github.com/JannisX11/hytale-blockbench-plugin` (official Blockbench exporter source)
- `https://github.com/hytale-tools/blockymodel-merger` (programmatic model merging reference)
- `https://jasonjgardner.github.io/blockbench-mcp-plugin/` (Blockbench MCP bridge reference)

## Verification

Run `.\scripts\hytale.ps1 verify -ProjectDir "<mod-dir>"` to enforce 32px-multiple PNG dimensions on 3D textures and run headless `HytaleServer.jar --validate-assets`.
