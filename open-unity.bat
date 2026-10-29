@echo off
rem 直接用本机 Unity 2022.3.42f1c1 打开本工程（不经过 Unity Hub）
rem 工程目录即本 .bat 所在目录
start "" "C:\Program Files\Unity 2022.3.42f1c1\Editor\Unity.exe" -projectPath "%~dp0."
