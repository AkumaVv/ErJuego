@echo off
del game.zip
"C:\Program Files\7-Zip\7z.exe" a game.zip Game.pck Game.exe
if "%1"=="commit" (
    git add .
    git commit -m "stuff"
    git push
)