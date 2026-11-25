---
name: hytale-gradle-manifest
description: "Trigger: gradle, build.gradle, manifest.json, shadowJar, hytale-tools, ServerVersion, IncludesAssetPack, Java 25, plugin setup. Configure Hytale 2026 Gradle builds, Java 25 toolchains, shadowJar relocation, and PascalCase manifest.json files."
license: MIT
allowed-tools: Read Write Edit Bash(pwsh:*) Bash(python:*)
metadata:
  trigger: ["gradle", "build.gradle", "manifest.json", "shadowJar", "hytale-tools", "ServerVersion", "IncludesAssetPack"]
  scope: [project]
  version: "1.0.0"
---

# Hytale Gradle & Manifest Setup

Use this skill when bootstrapping a Hytale 2026 server plugin or content pack, configuring Gradle, or authoring `manifest.json`.

## Core Rules

1. **Java 25 Toolchain**: Always target `JavaLanguageVersion.of(25)`. Do not use Java 17 or Java 21.
2. **Gradle Wrapper on Windows**: Always invoke `.\gradlew.bat` (never `./gradlew`). Run builds via `.\scripts\hytale.ps1 verify` so `JAVA_HOME` points to JDK 25.
3. **Preferred Gradle Plugin**: Prioritize `com.azuredoom.hytale-tools` (`1.0.52`) over legacy `ScaffoldIt` (`hytale {}` vs `hytaleTools {}`) when starting from `HytaleModding/plugin-template`.
4. **Official Maven Repositories**: Resolve `com.hypixel.hytale:Server:+` from `https://maven.hytale.com/release` (or `https://maven.hytale.com/pre-release`). For offline builds, use `compileOnly(files("libs/HytaleServer.jar"))`.
5. **Relocate Shaded Dependencies**: When bundling third-party libraries via `shadowJar`, always `relocate(...)` them to your plugin package namespace to prevent classpath collisions.

## Groovy DSL Template (`build.gradle`)

```groovy
plugins {
    id 'java'
    id 'com.azuredoom.hytale-tools' version '1.0.52'
}

group = 'com.example.mods'
version = '1.0.0'

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
}

hytaleTools {
    hytaleVersion = '0.+'
    patchline = 'release' // 'release' or 'pre-release'
    manifestGroup = 'com.example.mods'
    modId = 'examplemod'
    mainClass = 'com.example.mods.ExampleMod'
    modCredits = 'Author'
}

tasks.named('shadowJar') {
    archiveClassifier.set('')
    relocate('com.google.gson', 'com.example.mods.shaded.gson')
}
```

Key `com.azuredoom.hytale-tools` tasks: `setupHytaleDev`, `runServer`, `runAllMods`, `prepareDecompiledSourcesForIde`, `updatePluginManifest`, `hytaleDoctor`, `hytaleJvmDoctor`.

## `manifest.json` Specification (Strict PascalCase)

- Location for Java plugins: `src/main/resources/manifest.json`
- Location for Pure Asset Packs: `<pack-root>/manifest.json` (omit `Main`)
- Never use `plugin.yml`, `fabric.mod.json`, `neoforge.mods.toml`, or lowercase/camelCase keys.
- **Exact `ServerVersion`**: Since Update 3, `PluginManager` checks `ServerVersion` by exact string equality. Never hardcode `"*"` or SemVer ranges; retrieve the current server version via `.\scripts\hytale.ps1 env`.

| Key | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `Name` | `string` | Yes | Unique plugin/pack name; forms `Group:Name` |
| `Group` | `string` | Recommended | Maven-style namespace (e.g. `"com.example"`) |
| `Version` | `string` | Recommended | SemVer string (e.g. `"1.0.0"`) |
| `Description` | `string` | No | Human-readable module summary |
| `Authors` | `AuthorInfo[]` | No | Objects with optional `Name`, `Email`, `Url` |
| `Website` | `string` | No | Project or docs URL |
| `Main` | `string` | Yes (Java) | FQCN extending `JavaPlugin`; omit in pure asset packs |
| `ServerVersion` | `string` | Recommended | Exact target string from `HytaleServer.jar --version` |
| `Dependencies` | `Map<String, String>` | No | `"Group:Name": "<semver_range>"` |
| `OptionalDependencies` | `Map<String, String>` | No | Soft dependencies; guard at runtime |
| `LoadBefore` | `Map<String, String>` | No | Plugins initialized after this plugin |
| `DisabledByDefault` | `boolean` | No | Default `false` |
| `IncludesAssetPack` | `boolean` | Yes if assets | Must be `true` when bundling `Common/` or `Server/` |
| `SubPlugins` | `PluginManifest[]` | No | Nested manifests inheriting parent metadata |

## Curated Golden Reference Repositories

- `https://github.com/HytaleModding/plugin-template` (canonical `com.azuredoom.hytale-tools` project layout)
- `https://github.com/AzureDoom/Hytale-Gradle-Plugin` (`hytaleTools {}`, `hytaleDoctor`, JDWP/hot-swap flags)
- `https://github.com/Kaupenjoe/Hytale-Example-Plugin` (clean Kotlin DSL `build.gradle.kts` + Java 25)
- `https://github.com/HytaleModding/patcher` (Vineflower decompilation helper for deep core inspection)

> When cloning external repos for reference, scan files first with `prompt-shield` (`safe_read.py`).

## Verification

1. Run `.\scripts\hytale.ps1 env` to confirm JDK 25 and retrieve exact `ServerVersion`.
2. Run `.\scripts\hytale.ps1 verify -ProjectDir "<mod-dir>"` to validate `manifest.json`, build the JAR, and run headless `HytaleServer.jar --validate-assets --shutdown-after-validate`.
