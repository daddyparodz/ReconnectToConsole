# Reconnect To Console (Physical Session)

## Why

I got tired of logging in again every time I returned to my PC after using it through RDP, so I built a tiny Windows helper that switches the remote session back to the physical one using the real screen, keyboard, and mouse.

## What It Does

* Runs `tscon` against your current user session to attach it to the physical session
* Wraps the action in a scheduled task so it works from any shell (RDP, SSH, WinRM, etc.) and with the right privileges

## Features

* One command: `rtc` reconnects your RDP session to the physical display
* Installer adds a single `bin` folder to your user PATH (HKCU) and creates the `rtc` task
* Smart pre checks: installer skips if already installed; uninstaller skips if not installed
* `rtc` closes the launching CMD window on success (returns an error otherwise)

## Requirements

* Windows 10/11 or Windows Server with RDP enabled
* PowerShell 5.1 (inbox on Windows 10/11)
* Permission to manage your own sessions

## Install

* Choose where you want this tool to live permanently and clone or copy the repository there. The installer adds that folder’s `bin` subdirectory to your user PATH and the uninstall will remove that same path. If you move the folder later, run `uninstall.bat` and then reinstall from the new location.
* Run `install.bat` (no need to pre elevate; it will prompt for UAC).
* If already installed (PATH contains the tool and the `rtc` task exists) you’ll be told and nothing changes.

## Usage

* From any shell: `rtc`
* If started from a CMD window, it triggers the task and closes that window on success.
* If the task cannot be started, it prints a short error and leaves your shell open.

## Uninstall

* Run `uninstall.bat` (prompts for UAC).
* If not installed, you’ll be told and nothing changes.

## How It Works

* `ReconnectToConsole.bat` (root):

  * `query user %USERNAME%` to get your session ID
  * `tscon <id> /dest:console` to attach the session to the physical display

* `bin/rtc.bat`:

  * Runs `schtasks /run /tn rtc` quietly
  * Exits on success so interactive CMD windows close

* `install.bat`:

  * Elevates via UAC, resolves the canonical install path
  * Adds the `bin` folder to HKCU PATH (dedupes existing entries)
  * Registers a manual "On demand" task named `rtc` that runs `cmd.exe /c "ReconnectToConsole.bat"`
  * Uses Highest privileges and compatibility set to `Win8` (highest value exposed by the PowerShell ScheduledTasks module on Windows 10/11)
  * Skips work and reports "already installed" when appropriate

* `uninstall.bat`:

  * Elevates via UAC
  * Removes the `bin` entry from HKCU PATH and from the current session
  * Deletes the `rtc` task
  * Skips work and reports "not installed" when appropriate

## Troubleshooting

* “Access is denied” or elevation prompts keep appearing

  * Accept the UAC prompt, or start an elevated Command Prompt first

* `rtc` not found after install

  * Open a new shell, or run `set PATH` and confirm the `bin` folder is present

* Task runs but nothing moves

  * Make sure you are in an RDP session; verify with `query user`

## License

This project is licensed under the MIT License.  
See the [LICENSE](./LICENSE) file for details.