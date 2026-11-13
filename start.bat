@echo off
rem sabori_watch launcher: runs the watcher hidden in the background.
rem To stop it, end powershell.exe from Task Manager.
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0sabori_watch.ps1"
