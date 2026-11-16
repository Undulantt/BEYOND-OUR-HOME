@echo off
setlocal
set "BOH_REPO_ROOT=%~dp0"
powershell.exe -NoLogo -NoProfile -Command "& { $ErrorActionPreference = 'Stop'; try { $root = $env:BOH_REPO_ROOT; $zip = Join-Path $root 'JUGAR-WINDOWS.zip'; if (-not (Test-Path -LiteralPath $zip)) { throw 'No se encuentra JUGAR-WINDOWS.zip. Descomprime primero todo el ZIP del repositorio.' }; $version = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.Substring(0,12); $game = Join-Path (Join-Path $root 'juego_windows') $version; $ready = Join-Path $game '.listo'; if (-not (Test-Path -LiteralPath $ready)) { New-Item -ItemType Directory -Force -Path $game | Out-Null; Expand-Archive -LiteralPath $zip -DestinationPath $game -Force; Set-Content -LiteralPath $ready -Value $version }; $exe = Join-Path $game 'BEYOND OUR HOME.exe'; if (-not (Test-Path -LiteralPath $exe)) { throw 'El paquete no contiene el ejecutable. Extrae JUGAR-WINDOWS.zip manualmente.' }; Start-Process -FilePath $exe -WorkingDirectory $game } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 } }"
if errorlevel 1 pause
endlocal
