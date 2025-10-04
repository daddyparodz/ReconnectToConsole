@echo off
for /f "tokens=3" %%s in ('query user %USERNAME%') do (
    tscon %%s /dest:console
)