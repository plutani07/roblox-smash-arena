# Rebuilds place/RobloxSmashGames_Smash.rbxl from place/RobloxSmashGames.rbxl + src/
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /optimize /nowarn:675 /out:rbx.exe Zstd.cs Rbx.cs Dump.cs Main.cs Build.cs LuaCheck.cs
if ($LASTEXITCODE -ne 0) { throw "compile failed" }
.\rbx.exe lint ..\src
if ($LASTEXITCODE -ne 0) { throw "lint found problems" }
.\rbx.exe build ..\place\RobloxSmashGames.rbxl ..\src ..\place\RobloxSmashGames_Smash.rbxl
if ($LASTEXITCODE -ne 0) { throw "build failed" }
