# Hytale 2026 Modding Invariants & Anti-Hallucination Rules

All Hytale mods in this workspace target the **shipped 2026 server-authoritative architecture**: a **Java 25** server (`HytaleServer.jar`, `com.hypixel.hytale.*`) with a native Entity Component System (ECS), a data-driven **C# client** (no client-side Java code), and declarative `Common/` + `Server/` asset packs.

## 5 Non-Negotiable Invariants

1. **Java 25 Toolchain Always**: Compile and run strictly on **JDK 25** (`JavaLanguageVersion.of(25)`). System `PATH` may default to JDK 8; always execute builds and server checks through `.\scripts\hytale.ps1` or force `JAVA_HOME`.
2. **PascalCase `manifest.json` + Exact `ServerVersion`**: Use strict PascalCase keys (`Name`, `Group`, `Version`, `Main`, `ServerVersion`, `IncludesAssetPack`). Never hardcode or use `"*"` / SemVer ranges for `ServerVersion`; resolve the live value via `.\scripts\hytale.ps1 env`. Set `"IncludesAssetPack": true` whenever `Common/` or `Server/` resources are bundled.
3. **Plugin Lifecycle (`setup` / `start` / `shutdown`)**: Extend `com.hypixel.hytale.server.core.plugin.JavaPlugin` with constructor `JavaPlugin(JavaPluginInit init)` and override `setup()`, `start()`, and `shutdown()`. Never use `onEnable()` or `onDisable()`.
4. **ECS Concurrency & `WorldThread` Safety**: Separate data (`Component<EntityStore>` / `ChunkStore` + `BuilderCodec`) from behavior (`EntityTickingSystem`). Queue structural changes in `CommandBuffer` during `tick()`, always check `ref.isValid()`, never return `null` from `getQuery()`, and marshal off-thread callbacks back via `world.execute(() -> ...)`.
5. **CLI Verification Before Completion**: Run `.\scripts\hytale.ps1 verify -ProjectDir <path>` (static validation + Gradle build + headless `HytaleServer.jar` check) before claiming a mod works.

## Mandatory `javap` Verification Rule

Never import or call an unverified `com.hypixel.hytale.*` class, enum constant, or method signature from memory or `[Community/Unverified]` docs. Inspect the local binary first:

```powershell
.\scripts\hytale.ps1 javap -ClassName com.hypixel.hytale.server.core.plugin.JavaPlugin
```

## Anti-Hallucination Matrix (12 Blocked Patterns)

| Hallucinated Pattern (Minecraft / Pre-2026) | Why It Fails in Hytale 2026 | Verified 2026 Equivalent |
| :--- | :--- | :--- |
| C++ server rewrite or JS/Lua/TS scripting | Reflects cancelled pre-2026 rumors | Java 25 plugins against `HytaleServer.jar` + JSON / `.ui` assets |
| `plugin.yml`, `fabric.mod.json`, `neoforge.mods.toml`, lowercase keys | Hytale loader ignores them and requires PascalCase | `src/main/resources/manifest.json` with PascalCase keys |
| `"ServerVersion": "*"` or SemVer ranges | Post-Update 3 enforces exact string match | Exact version parsed via `.\scripts\hytale.ps1 env` |
| `onEnable()`, `onDisable()`, `Listener`, `@EventHandler` | Bukkit/Paper API does not exist in core | `JavaPlugin(JavaPluginInit)` + `setup()`, `start()`, `shutdown()` |
| `Bukkit.getPluginManager().registerEvents(...)`, `CommandExecutor` | Non-existent classes | `getEventRegistry().registerGlobal(...)` / `EntityEventSystem`, `AbstractCommand` / `AbstractPlayerCommand` |
| OOP `extends LivingEntity` / `BlockEntity` | Hytale uses archetype-based ECS | `Component<EntityStore>` / `ChunkStore` + `BuilderCodec` + `EntityTickingSystem` |
| Direct `Store` mutation in `tick()` or off-thread world access | Corrupts archetype iteration or fails `assertThread()` | `CommandBuffer`, `ref.isValid()`, `world.execute(() -> ...)` |
| Fabric `@Mixin` / `@Inject` | No Mixin runtime in Hytale | Early Plugins (`ClassTransformer` + ASM 9.8 in `META-INF/services/`) + `--accept-early-plugins` |
| Client `Screen`, `GuiGraphics`, custom binary packets | C# client runs zero mod Java code | `.ui` under `Common/UI/Custom/` + `InteractiveCustomUIPage<Data>` + mandatory `sendUpdate()` |
| Hytale Model Maker, PBR maps (`_n.png`, `_s.png`), spheres, 16px density | Tool retired; engine forbids PBR and spheres | Blockbench + `JannisX11/hytale-blockbench-plugin`, cubes/quads only, 32px multiples, stretch `0.7x-1.3x` |
| `docs.shard.hytalemodding.dev` (`Shard.Network.*`) | Third-party C# server reimplementation | `com.hypixel.hytale.*` in `docs.hytale.com` or local `javap` |
| Java 17 or Java 21 in Gradle | `HytaleServer.jar` bytecode requires Java 25 | `JavaLanguageVersion.of(25)` (Adoptium/Oracle JDK 25 LTS) |
