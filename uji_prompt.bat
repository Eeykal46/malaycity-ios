@echo off
setlocal enabledelayedexpansion
set "MSG="
set /p "MSG=Prompt: "
echo DEBUG-[!MSG!]-END
if "!MSG!"=="" (echo KOSONG) else (echo ADA)
