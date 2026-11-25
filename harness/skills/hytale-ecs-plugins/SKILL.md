---
name: hytale-ecs-plugins
description: "Trigger: JavaPlugin, ECS, Component, EntityTickingSystem, CommandBuffer, WorldThread, AbstractCommand, EventRegistry, PermissionsModule, PacketAdapters, Early Plugin. Author Java 25 Hytale server plugins using the official com.hypixel.hytale.* ECS, command, event, and concurrency APIs."
license: MIT
allowed-tools: Read Write Edit Bash(pwsh:*) Bash(python:*)
metadata:
  trigger: ["JavaPlugin", "ECS", "EntityTickingSystem", "CommandBuffer", "WorldThread", "AbstractCommand", "EventRegistry", "PacketAdapters"]
  scope: [project]
  version: "1.0.0"
---

# Hytale Server Plugins & ECS Architecture (`com.hypixel.hytale.*`)

Use this skill when writing Java 25 server plugins, ECS components/systems, commands, event listeners, permissions, or packet adapters.

## Mandatory Signature Check

Before introducing an unverified import or method call under `com.hypixel.hytale.*`, inspect the local server binary:

```powershell
.\scripts\hytale.ps1 javap -ClassName <FQCN>
```

Never consult `docs.shard.hytalemodding.dev` (`Shard.Network.*`) — that is an unrelated C# server project.

## Plugin Lifecycle (`JavaPlugin`)

- Extend `com.hypixel.hytale.server.core.plugin.JavaPlugin` (subclass of `PluginBase`).
- Constructor MUST accept `com.hypixel.hytale.server.core.plugin.JavaPluginInit` (never `com.hypixel.hytale.plugin.JavaPluginInit`) and delegate via `super(init)`.
- Override `setup()`, `start()`, and `shutdown()` (never `onEnable()` / `onDisable()`):
  - `setup()`: register ECS components (`getEntityStoreRegistry().registerComponent(...)`), systems (`registerSystem(...)`), commands (`getCommandRegistry().registerCommand(...)`), global event listeners (`getEventRegistry().registerGlobal(...)`), and asset stores (`getAssetRegistry().register(...)`).
  - `start()`: execute logic requiring all dependencies to be registered.
  - `shutdown()`: deterministically release resources on stop or `/plugin reload`.

## ECS & `WorldThread` Concurrency Rules

- **Data vs Behavior**: Store state in `Component<EntityStore>` (entities/players) or `Component<ChunkStore>` (block/chunk data) serialized with `BuilderCodec` + `KeyedCodec`, and world-level shared state in `Resource<T>` (avoid mutable static globals).
- **Injection Pattern**: Inject `ComponentType<EntityStore, MyComponent>` into systems and commands via constructors (avoid broken `this.type` static references).
- **Defensive Checks**:
  - Always check `ref.isValid()` and guard against `null` returns from `archetypeChunk.getComponent(index, type)` (mitigates known vanilla despawn `IndexOutOfBoundsException` bugs documented in `hyfixes`).
  - Never return `null` from `getQuery()` (`ComponentRegistry` throws `NullPointerException`). Use `Query.and(...)`, `OrQuery`, `NotQuery`, etc.
- **Structural Mutations & Threading**:
  - Inside `EntityTickingSystem.tick(...)`, enqueue component/entity additions or removals via `CommandBuffer` (e.g., `commandBuffer.removeComponent(ref, type)`), never mutate `Store` directly during iteration.
  - Each `World` ticks its `Store` on its own `WorldThread` guarded by `assertThread()`. Off-thread callbacks (`PacketAdapters`, `SCHEDULED_EXECUTOR`, `CompletableFuture`) MUST re-enter via `world.execute(() -> { ... })`.

## Commands, Events, Permissions & Networking

- **Commands**: Extend `AbstractCommand`, `AbstractPlayerCommand` (injects `Store<EntityStore>`, `Ref<EntityStore>`, `PlayerRef`, `World`), or `AbstractWorldCommand`; register via `getCommandRegistry().registerCommand(...)`.
- **Events**: Global server lifecycle events (`PlayerReadyEvent`, `PlayerChatEvent`, `LoadedAssetsEvent`, `GenerateSchemaEvent`) use `getEventRegistry().registerGlobal(...)` or `register(...)`. Typed ECS events inside a `Store` use `EntityEventSystem`, `DamageEventSystem`, or `WorldEventSystem`.
- **Permissions**: Check via `CommandSender#hasPermission(String)`; standard constants live in `HytalePermissions` (`COMMAND_BASE`, `ASSET_EDITOR`, `FLY_CAM`, `fromCommand(name)`).
- **Networking**: Hytale uses QUIC (UDP 5520). There is no official API to register arbitrary custom binary packets because the C# client runs no mod Java code. Synchronize state via synced ECS components, `UICommandBuilder`, and `WindowManager`; intercept existing protocol packets via `PacketAdapters.registerInbound(handler)`.
- **Early Plugins (Advanced / Unsupported)**: Implement `com.hypixel.hytale.plugin.early.ClassTransformer` with ASM 9.8, register under `META-INF/services/com.hypixel.hytale.plugin.early.ClassTransformer`, and boot with `--accept-early-plugins`.

## Minimal Reference Skeleton

```java
public final class ExamplePlugin extends JavaPlugin {
    private ComponentType<EntityStore, ExampleComponent> exampleType;

    public ExamplePlugin(@Nonnull JavaPluginInit init) {
        super(init);
    }

    @Override
    protected void setup() {
        this.exampleType = getEntityStoreRegistry()
            .registerComponent(ExampleComponent.class, ExampleComponent::new);
        getEntityStoreRegistry().registerSystem(new ExampleSystem(this.exampleType));
        getCommandRegistry().registerCommand(new ExampleCommand(this.exampleType));
        getEventRegistry().registerGlobal(PlayerReadyEvent.class, this::onPlayerReady);
    }

    private void onPlayerReady(@Nonnull PlayerReadyEvent event) {
        // Player connected logic
    }
}
```

## Curated Golden Reference Repositories

- `https://github.com/zkiller/HytaleEnergyStorage` (canonical ECS block/entity components + deterministic per-tick transfer)
- `https://github.com/Buuz135/SimpleClaims` (chunk protection and ECS patterns)
- `https://github.com/cryptobench/EasyClaims` (chunk claims + `javap` / `assertThread()` / `world.execute()` agent conventions)
- `https://github.com/John-Willikers/hyfixes` (`HYTALE_CORE_BUGS.md` core race conditions and defensive patterns)
- `https://github.com/maksimovc/WorldHeightY320Plus` (ASM 9.8 `ClassTransformer` Early Plugin reference)

## Verification

1. Confirm unverified `com.hypixel.hytale.*` packages with `.\scripts\hytale.ps1 javap -ClassName <FQCN>`.
2. Run `.\scripts\hytale.ps1 verify -ProjectDir "<mod-dir>"` to compile with JDK 25 and verify `PluginManager` loading cleanly.
