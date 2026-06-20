# DockOS Paralimni 0.0.1

DockOS Paralimni is a clean DockOS rewrite for CC:Tweaked Advanced Computers with Tom's Peripherals GPU output.

## Install

When this repository is pushed to GitHub:

```lua
wget https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/main/dock-installer.lua dock-installer.lua
dock-installer.lua
dock
```

For automatic boot, run `startup` after installation or reboot the computer.

## Runtime Requirements

- CC:Tweaked Advanced Computer.
- Tom's Peripherals GPU for bitmap desktop mode.
- Keyboard peripheral for direct monitor input.
- 3x6 monitor is the primary target for Paralimni 0.0.1.

If no bitmap GPU is found, DockOS starts a terminal fallback with the same backend commands.

## Commands

```lua
dock about
dock version
dock services
dock ps
dock devices
dock apps
dock run <app_id>
dock files
dock ls <path>
dock open <path>
dock install-local <path>
dock uninstall <app_id>
dock settings get <key>
dock settings set <key> <value>
dock test
```

## System Layout

- `startup.lua` boots the desktop.
- `dock.lua` runs DockOS commands or desktop mode.
- `dock/system` contains kernel services.
- `dock/apps/system` contains built-in app manifests.
- `dock/assets` contains generated wallpaper assets for supported GPU sizes.
- `dock/tests/selftest.lua` validates backend services inside CC:Tweaked.

## Desktop Model

- Top-left black DockOS menu opens About, Reboot, and Shutdown.
- Top menu labels expose current app actions.
- Bottom dock has pinned apps on the left, a pixel divider, and unpinned open apps on the right.
- Right-click an app icon to keep or remove it from the dock.
- Drag a dock icon across the divider to pin or unpin it.
- Drag empty desktop space to draw a selection rectangle.
- Windows use left-side close, hide, and fullscreen controls.
