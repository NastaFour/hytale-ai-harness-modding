<#
.SYNOPSIS
    Unified CLI for the Hytale 2026 Modding AI Coding Agent Harness.
.DESCRIPTION
    Provides spaces-safe, $PSScriptRoot-relative automation for:
      - env     : Configure JDK 25, validate Hytale paths, and parse live ServerVersion
      - javap   : Inspect compiled com.hypixel.hytale.* classes in HytaleServer.jar
      - verify  : Run validate_mod.py, Gradle build, and isolated headless HytaleServer.jar check
      - schemas : Extract official JSON Schemas via HytaleServer.jar --generate-schema
#>
[CmdletBinding()]
param(
    [Parameter(Position=0, Mandatory = $true)]
    [ValidateSet("env", "javap", "verify", "schemas")]
    [string]$Command,

    [string]$ClassName,
    [switch]$Private,
    [switch]$Signatures,

    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot),
    [switch]$SmokeTest,
    [switch]$SkipGradle,
    [ValidateSet("shadowJar", "build")]
    [string]$GradleTask = "shadowJar",
    [switch]$ValidateAssets,
    [switch]$ValidateWorldGen,
    [switch]$UseAOT,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = Split-Path -Parent $PSScriptRoot

function Format-CliArg {
    param([string]$Value)
    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

function Invoke-NativeQuiet {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $Executable @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
    return [PSCustomObject]@{
        ExitCode = $code
        Output   = ($output | Out-String).Trim()
    }
}

function Initialize-HytaleEnv {
    $jdkHome = if ($env:HYTALE_JDK_HOME) { $env:HYTALE_JDK_HOME } else { "C:\Program Files\Java\jdk-25" }
    $jdkBin = Join-Path $jdkHome "bin"
    $javaExe = Join-Path $jdkBin "java.exe"
    $javapExe = Join-Path $jdkBin "javap.exe"

    if (-not (Test-Path -LiteralPath $javaExe)) {
        Write-Error "JDK 25 java.exe not found at '$javaExe'. Install JDK 25 or set HYTALE_JDK_HOME."
        exit 1
    }
    if (-not (Test-Path -LiteralPath $javapExe)) {
        Write-Error "JDK 25 javap.exe not found at '$javapExe'."
        exit 1
    }

    $env:JAVA_HOME = $jdkHome
    $pathParts = @($env:PATH -split ";" | Where-Object { $_ -ne "" })
    if ($pathParts.Count -eq 0 -or ($pathParts[0].TrimEnd("\") -ine $jdkBin.TrimEnd("\"))) {
        $filtered = $pathParts | Where-Object { $_.TrimEnd("\") -ine $jdkBin.TrimEnd("\") }
        $env:PATH = (@($jdkBin) + $filtered) -join ";"
    }

    $hytaleHome = if ($env:HYTALE_HOME) {
        $env:HYTALE_HOME
    }
    else {
        Join-Path $env:APPDATA "Hytale\install\release\package\game\latest"
    }
    $serverJar = Join-Path $hytaleHome "Server\HytaleServer.jar"
    $aotPath = Join-Path $hytaleHome "Server\HytaleServer.aot"
    $assetsZip = Join-Path $hytaleHome "Assets.zip"

    if (-not (Test-Path -LiteralPath $serverJar)) {
        Write-Error "HytaleServer.jar not found at '$serverJar'. Verify Hytale installation or set HYTALE_HOME."
        exit 1
    }
    if (-not (Test-Path -LiteralPath $assetsZip)) {
        Write-Error "Assets.zip not found at '$assetsZip'."
        exit 1
    }

    $verRes = Invoke-NativeQuiet -Executable $javaExe -Arguments @("-jar", $serverJar, "--version")
    if ($verRes.ExitCode -ne 0) {
        Write-Error "Failed to query HytaleServer.jar --version (exit $($verRes.ExitCode)): $($verRes.Output)"
        exit 1
    }

    $serverVersion = ""
    if ($verRes.Output -match '(?:^|\s)v(\d[^\s]*)') {
        $serverVersion = $Matches[1]
    }
    else {
        Write-Error "Could not parse ServerVersion from output: $($verRes.Output)"
        exit 1
    }

    $javaVerRes = Invoke-NativeQuiet -Executable $javaExe -Arguments @("-version")

    $env:HYTALE_HOME = $hytaleHome
    $env:HYTALE_SERVER_JAR = $serverJar
    $env:HYTALE_AOT = $aotPath
    $env:HYTALE_ASSETS_ZIP = $assetsZip
    $env:HYTALE_SERVER_VERSION = $serverVersion

    return [PSCustomObject]@{
        JavaHome      = $jdkHome
        JavaExe       = $javaExe
        JavapExe      = $javapExe
        JavaVersion   = ($javaVerRes.Output -split "`r?`n")[0]
        HytaleHome    = $hytaleHome
        ServerJar     = $serverJar
        AotPath       = $aotPath
        AssetsZip     = $assetsZip
        ServerVersion = $serverVersion
        RawVersion    = $verRes.Output
    }
}

function Invoke-IsolatedServer {
    param(
        [pscustomobject]$EnvInfo,
        [string[]]$ServerArgs,
        [int]$TimeoutSec,
        [switch]$EnableAOT
    )
    $tempDir = Join-Path $env:TEMP ("hytale-harness-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $jvmArgs = New-Object System.Collections.Generic.List[string]
    if ($EnableAOT -and (Test-Path -LiteralPath $EnvInfo.AotPath)) {
        $jvmArgs.Add("-XX:AOTCache=" + $EnvInfo.AotPath)
    }
    $jvmArgs.Add("-Xmx4G")
    $jvmArgs.Add("-jar")
    $jvmArgs.Add($EnvInfo.ServerJar)
    foreach ($a in $ServerArgs) {
        $jvmArgs.Add($a)
    }

    $argString = ($jvmArgs | ForEach-Object { Format-CliArg $_ }) -join " "

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $EnvInfo.JavaExe
    $psi.Arguments = $argString
    $psi.WorkingDirectory = $tempDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    Push-Location $tempDir
    try {
        [void]$proc.Start()
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $finished = $proc.WaitForExit($TimeoutSec * 1000)
        if (-not $finished) {
            try { $proc.Kill() } catch {}
            return [PSCustomObject]@{
                ExitCode    = 1
                TimedOut    = $true
                TempDir     = $tempDir
                LogText     = "Timed out after ${TimeoutSec}s."
                CreatedJson = @()
            }
        }
        $proc.WaitForExit()
        $exitCode = [int]$proc.ExitCode
        $stdoutText = $stdoutTask.GetAwaiter().GetResult()
        $stderrText = $stderrTask.GetAwaiter().GetResult()
        $combined = ($stdoutText + "`n" + $stderrText).Trim()

        $jsonFiles = @(Get-ChildItem -Path $tempDir -Recurse -Filter "*.json" -File -ErrorAction SilentlyContinue)

        return [PSCustomObject]@{
            ExitCode    = $exitCode
            TimedOut    = $false
            TempDir     = $tempDir
            LogText     = $combined
            CreatedJson = $jsonFiles
        }
    }
    finally {
        $proc.Dispose()
        Pop-Location
    }
}

$envInfo = Initialize-HytaleEnv

switch ($Command) {
    "env" {
        Write-Host "JAVA_HOME            : $($envInfo.JavaHome)"
        Write-Host "Java Runtime         : $($envInfo.JavaVersion)"
        Write-Host "HYTALE_HOME          : $($envInfo.HytaleHome)"
        Write-Host "HYTALE_SERVER_JAR    : $($envInfo.ServerJar)"
        Write-Host "HYTALE_ASSETS_ZIP    : $($envInfo.AssetsZip)"
        Write-Host "HYTALE_SERVER_VERSION: $($envInfo.ServerVersion)"
        exit 0
    }

    "javap" {
        if ([string]::IsNullOrWhiteSpace($ClassName)) {
            Write-Error "javap subcommand requires -ClassName <FQCN>."
            exit 2
        }
        $javapArgs = New-Object System.Collections.Generic.List[string]
        if ($Private) { $javapArgs.Add("-p") }
        if ($Signatures) { $javapArgs.Add("-s") }
        $javapArgs.Add("-classpath")
        $javapArgs.Add($envInfo.ServerJar)
        $javapArgs.Add($ClassName)

        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $envInfo.JavapExe @javapArgs
            $code = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $prev
        }
        exit $code
    }

    "schemas" {
        $targetDir = Join-Path $WorkspaceRoot ".hytale-harness\schemas"
        $res = Invoke-IsolatedServer -EnvInfo $envInfo `
            -ServerArgs @("--generate-schema", "--assets", $envInfo.AssetsZip, "--bare", "--auth-mode", "offline", "--disable-sentry") `
            -TimeoutSec $TimeoutSeconds `
            -EnableAOT:$UseAOT

        try {
            if ($res.TimedOut -or $res.ExitCode -ne 0) {
                Write-Error "Schema generation failed (exit $($res.ExitCode), timedOut=$($res.TimedOut)):`n$($res.LogText)"
                exit 1
            }

            $allJsons = @($res.CreatedJson)
            $assetsParent = Split-Path -Parent $envInfo.AssetsZip
            $siblingSchemaDir = Join-Path $assetsParent "Schema"
            if ($allJsons.Count -eq 0 -and (Test-Path -LiteralPath $siblingSchemaDir)) {
                $allJsons = @(Get-ChildItem -Path $siblingSchemaDir -Recurse -Filter "*.json" -File)
            }

            if ($allJsons.Count -eq 0) {
                Write-Error "Schema generation exited 0 but produced 0 .json files.`n$($res.LogText)"
                exit 1
            }

            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            foreach ($jf in $allJsons) {
                Copy-Item -LiteralPath $jf.FullName -Destination (Join-Path $targetDir $jf.Name) -Force
            }
            Write-Host "Extracted $($allJsons.Count) JSON schema file(s) to '$targetDir'."
            exit 0
        }
        finally {
            Remove-Item -LiteralPath $res.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    "verify" {
        $fatalPluginRegex = '(?im)(Failed to load plugin|Failed to setup|Failed to start|PluginManager.*(ERROR|Exception))'

        if ($SmokeTest) {
            $smokeTemp = Join-Path $env:TEMP ("hytale-smoke-mods-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $smokeTemp -Force | Out-Null
            try {
                $srvArgs = New-Object System.Collections.Generic.List[string]
                $srvArgs.Add("--assets"); $srvArgs.Add($envInfo.AssetsZip)
                $srvArgs.Add("--mods"); $srvArgs.Add($smokeTemp)
                $srvArgs.Add("--bare")
                $srvArgs.Add("--auth-mode"); $srvArgs.Add("offline")
                $srvArgs.Add("--disable-sentry")
                if ($ValidateAssets -or $ValidateWorldGen) {
                    $srvArgs.Add("--validate-assets")
                    if ($ValidateWorldGen) { $srvArgs.Add("--validate-world-gen") }
                    $srvArgs.Add("--shutdown-after-validate")
                }
                else {
                    $srvArgs.Add("--boot-command"); $srvArgs.Add("stop")
                }

                $res = Invoke-IsolatedServer -EnvInfo $envInfo -ServerArgs $srvArgs -TimeoutSec $TimeoutSeconds -EnableAOT:$UseAOT
                try {
                    if ($res.TimedOut -or $res.ExitCode -ne 0) {
                        Write-Error "SmokeTest failed (exit $($res.ExitCode), timedOut=$($res.TimedOut)):`n$($res.LogText)"
                        exit 1
                    }
                    if ($res.LogText -match $fatalPluginRegex) {
                        Write-Error "SmokeTest detected fatal PluginManager errors:`n$($res.LogText)"
                        exit 1
                    }
                    $lines = @($res.LogText -split "`r?`n")
                    $tail = ($lines | Select-Object -Last 10) -join "`n"
                    Write-Host "SmokeTest PASSED (ServerVersion=$($envInfo.ServerVersion), exit=$($res.ExitCode))."
                    if ($tail) { Write-Host $tail }
                    exit 0
                }
                finally {
                    Remove-Item -LiteralPath $res.TempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item -LiteralPath $smokeTemp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not (Test-Path -LiteralPath $ProjectDir)) {
            Write-Error "ProjectDir does not exist: '$ProjectDir'"
            exit 2
        }

        $validatorScript = Join-Path $PSScriptRoot "validate_mod.py"
        $schemasDir = Join-Path $WorkspaceRoot ".hytale-harness\schemas"
        $pyArgs = @($validatorScript, $ProjectDir, "--server-version", $envInfo.ServerVersion)
        if (Test-Path -LiteralPath $schemasDir) {
            $pyArgs += @("--schemas-dir", $schemasDir)
        }

        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & python @pyArgs
            $pyCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $prev
        }
        if ($pyCode -ne 0) {
            Write-Error "Static validation failed with exit code $pyCode."
            exit $pyCode
        }

        $gradlewBat = Join-Path $ProjectDir "gradlew.bat"
        $isGradle = Test-Path -LiteralPath $gradlewBat
        if ($isGradle -and -not $SkipGradle) {
            $effectiveTask = $GradleTask
            if ($effectiveTask -eq "shadowJar") {
                $buildScriptText = ""
                foreach ($bf in @("build.gradle", "build.gradle.kts")) {
                    $bfPath = Join-Path $ProjectDir $bf
                    if (Test-Path -LiteralPath $bfPath) {
                        $buildScriptText += (Get-Content -LiteralPath $bfPath -Raw)
                    }
                }
                if ($buildScriptText -notmatch 'shadowJar') {
                    $effectiveTask = "build"
                }
            }

            Push-Location $ProjectDir
            try {
                $prev = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                try {
                    & $gradlewBat $effectiveTask
                    $gradleCode = $LASTEXITCODE
                }
                finally {
                    $ErrorActionPreference = $prev
                }
                if ($gradleCode -ne 0) {
                    Write-Error "Gradle '$effectiveTask' failed with exit code $gradleCode."
                    exit $gradleCode
                }
            }
            finally {
                Pop-Location
            }
        }

        $modsPath = if ($isGradle) { Join-Path $ProjectDir "build\libs" } else { $ProjectDir }
        if (-not (Test-Path -LiteralPath $modsPath)) {
            Write-Error "Expected mods directory not found: '$modsPath'"
            exit 1
        }

        $srvArgs = New-Object System.Collections.Generic.List[string]
        $srvArgs.Add("--assets"); $srvArgs.Add($envInfo.AssetsZip)
        $srvArgs.Add("--mods"); $srvArgs.Add($modsPath)
        $srvArgs.Add("--bare")
        $srvArgs.Add("--auth-mode"); $srvArgs.Add("offline")
        $srvArgs.Add("--disable-sentry")
        if ($ValidateAssets -or $ValidateWorldGen) {
            $srvArgs.Add("--validate-assets")
            if ($ValidateWorldGen) { $srvArgs.Add("--validate-world-gen") }
            $srvArgs.Add("--shutdown-after-validate")
        }
        else {
            $srvArgs.Add("--boot-command"); $srvArgs.Add("stop")
        }

        $res = Invoke-IsolatedServer -EnvInfo $envInfo -ServerArgs $srvArgs -TimeoutSec $TimeoutSeconds -EnableAOT:$UseAOT
        try {
            if ($res.TimedOut -or $res.ExitCode -ne 0) {
                Write-Error "Headless verification failed (exit $($res.ExitCode), timedOut=$($res.TimedOut)):`n$($res.LogText)"
                exit 1
            }
            if ($res.LogText -match $fatalPluginRegex) {
                Write-Error "Headless verification detected PluginManager error:`n$($res.LogText)"
                exit 1
            }
            Write-Host "Verification PASSED for '$ProjectDir' (ServerVersion=$($envInfo.ServerVersion), exit=$($res.ExitCode))."
            exit 0
        }
        finally {
            Remove-Item -LiteralPath $res.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
