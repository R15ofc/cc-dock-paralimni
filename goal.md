You are working on a brand new CC:Tweaked operating system project.

Project name:
DockOS

Release:
DockOS Paralimni 0.0.1

Important context:
The previous generation was called Kyrenia. Paralimni is a full rewrite from scratch. Do not patch the old architecture. Design a clean backend-first foundation that can later support a real desktop UI.

Target environment:
- Minecraft CC:Tweaked
- Lua / CraftOS-compatible code
- Advanced Computer / normal Computer support where possible
- Optional support for Tom's Peripherals:
  - bitmap monitors / GPU
  - keyboard
  - redstone port
  - watchdog timer
- The OS must still work without Tom's Peripherals using normal CC:Tweaked terminal/peripherals as fallback.

Main goal:
Build DockOS as a real OS-like backend, not a toy launcher with fixed apps.

This means:
- Real filesystem layout
- Real user directories
- Real app registry
- Real file categories
- Real desktop entries
- Real settings storage
- Real services
- Real app installation model
- Real process/service management
- Real logs
- Real device/peripheral detection
- Real package/app manifests
- Real shell commands
- Everything must be data-driven, not hardcoded.

Do not build a fake OS where apps are just hardcoded buttons.
Do not make the desktop a static menu.
Do not make “Documents”, “Desktop”, “Downloads”, etc. just visual tabs.
They must be actual directories and actual filesystem concepts.

Use English for all code names, logs, errors, commands, and internal strings.
Do not add Russian comments or Russian output.
Keep code clean and production-like.

Architecture requirement:
Create a modular backend with clear separation between:
1. Bootloader
2. Kernel
3. Filesystem service
4. User/profile service
5. App registry
6. Package manager
7. Service manager
8. Process manager
9. Event bus
10. Settings/config service
11. Device/peripheral manager
12. Tom's Peripherals adapter
13. Notification/log service
14. Network/rednet service
15. Shell command layer
16. Minimal frontend/demo layer only for testing the backend

Expected filesystem layout:

/startup.lua
/dock/
  system/
    boot.lua
    kernel.lua
    version.lua
    paths.lua
    event_bus.lua
    service_manager.lua
    process_manager.lua
    logger.lua
    json.lua
    safe_io.lua
    registry.lua
    settings_service.lua
    user_service.lua
    fs_service.lua
    app_service.lua
    package_service.lua
    device_service.lua
    tom_adapter.lua
    net_service.lua
    notification_service.lua
    shell_service.lua
  apps/
    system/
      files/
        app.json
        main.lua
      terminal/
        app.json
        main.lua
      settings/
        app.json
        main.lua
    installed/
  users/
    default/
      Desktop/
      Documents/
      Downloads/
      Pictures/
      Music/
      Videos/
      Apps/
      Trash/
      .config/
      .local/
        share/
          applications/
          metadata/
  etc/
    system.json
    users.json
    apps.json
    services.json
    mime.json
    file_categories.json
    permissions.json
  var/
    log/
    cache/
    db/
    run/
  tmp/
  tests/

The paths do not have to use a leading slash internally if CC:Tweaked filesystem prefers relative root paths.
Use fs.combine everywhere. Do not concatenate paths manually with "/".

Version identity:
Implement a version module returning:

name = "DockOS"
codename = "Paralimni"
version = "0.0.1"
channel = "dev"
previous_codename = "Kyrenia"

Boot requirements:
- startup.lua must be tiny.
- startup.lua should only load DockOS boot.
- On first boot, DockOS must initialize the required directory tree and default databases.
- Boot must be safe if directories/files already exist.
- Boot must not destroy user files.
- Boot must validate core files and recover from missing optional files.
- Boot must start kernel, service manager, device manager, app registry, settings service, and shell/demo UI.
- Add a clear boot log in /dock/var/log/boot.log.

Storage requirements:
Use JSON or serialized tables consistently.
Create a small json.lua wrapper so the rest of the OS does not directly depend on textutils everywhere.
All writes to important files must be safe:
- write to temporary file
- close handle
- move/replace final file
- return clear success/error result

Do not silently fail.

Filesystem service:
Implement fs_service as an OS-level abstraction over CC:Tweaked fs.

It must support:
- create file
- read file
- write file
- append file
- create directory
- list directory
- copy
- move
- rename
- delete
- move to Trash
- restore from Trash
- permanent delete
- file exists
- directory exists
- get size
- get attributes if available
- search by name
- search by category
- get file type / mime-like type
- get user folders
- create desktop shortcut
- resolve desktop shortcut
- open file through app association

Real categories:
Implement file categories based on:
- actual folder location
- file extension
- metadata
- app associations

Default categories:
- Desktop
- Documents
- Downloads
- Pictures
- Music
- Videos
- Apps
- System
- Trash
- Unknown

Examples:
- .txt, .md, .log => document/text
- .lua => code/lua
- .nfp, .nft, .png if supported by Tom GPU/image APIs => image
- .app.json or app.json => application manifest
- .link.json => desktop shortcut

Desktop:
Desktop must be a real folder:
/dock/users/default/Desktop

Desktop items should be files, shortcuts, or app links.
A desktop shortcut should be a JSON file, for example:

{
  "type": "shortcut",
  "name": "My Notes",
  "target": "dock/users/default/Documents/notes.txt",
  "icon": "document",
  "created_at": 12345
}

The desktop renderer later should read this folder. Do not hardcode desktop icons in UI code.

User service:
Implement at least one default user:
id = "default"
name = "Default User"
home = "dock/users/default"

Prepare the architecture for multiple users later, but do not overbuild authentication in 0.0.1.
User service must provide:
- getCurrentUser()
- getHome()
- getUserPath(category)
- ensureUserFolders()
- getUserConfig()
- setUserConfig()

Settings service:
Settings must be persistent and separated into:
- system settings
- user settings
- app settings

Example paths:
- /dock/etc/system.json
- /dock/users/default/.config/user.json
- /dock/users/default/.config/apps/<app_id>.json

Support:
- get(key, default)
- set(key, value)
- save()
- load()
- watch/emit setting_changed event if possible

App system:
Do not hardcode apps into the OS.

Every app must have a manifest app.json:

{
  "id": "dock.files",
  "name": "Files",
  "version": "0.0.1",
  "entry": "main.lua",
  "type": "system",
  "category": "system",
  "icon": "folder",
  "permissions": ["fs.read", "fs.write"],
  "file_associations": ["folder", "text/plain"],
  "autoload": false,
  "desktop": true
}

The app registry must scan:
- /dock/apps/system
- /dock/apps/installed
- /dock/users/default/Apps

App service must support:
- scan apps
- validate manifest
- register app
- unregister app
- get app by id
- list apps
- list apps by category
- list apps for desktop
- launch app by id
- open file with app
- resolve file association
- install local app package
- remove installed app

System apps can exist, but they must still be manifest-driven.
Files, Terminal, and Settings can be included as system apps for testing, but the OS must not rely on a fixed list in the desktop.

Package manager:
Implement a minimal local package manager for 0.0.1.

It must support:
- install app from local directory
- validate app.json
- copy app into /dock/apps/installed/<app_id>
- register app
- uninstall app
- list installed packages
- update app metadata
- reject invalid packages

Prepare clean interfaces for future HTTP/Gist/DPL package sources, but do not fake a remote store if there is no real source yet.

Process manager:
Implement a simple process abstraction.

A process should have:
- pid
- name
- app_id or service_id
- status: running/stopped/crashed
- started_at
- last_error
- coroutine/task function if applicable

Support:
- spawn
- stop
- list
- get
- crash handling with pcall
- event delivery where possible

Do not let one app crash the entire OS.
If an app crashes, log it and return to shell/desktop.

Service manager:
Services are background modules.

Support:
- register service
- start service
- stop service
- restart service
- list services
- health/status
- autostart services from /dock/etc/services.json

Core services:
- logger
- settings
- fs
- app_registry
- devices
- notifications
- net/rednet if modem exists
- watchdog if Tom's Peripherals watchdog exists

Event bus:
Implement an internal event bus.

Support:
- emit(event_name, payload)
- subscribe(event_name, handler)
- unsubscribe
- safe handler execution
- system events:
  - boot_started
  - boot_completed
  - service_started
  - service_stopped
  - app_installed
  - app_removed
  - app_launched
  - file_created
  - file_deleted
  - file_moved
  - setting_changed
  - peripheral_attached
  - peripheral_detached
  - network_message
  - process_crashed

Device manager:
Use peripheral APIs to discover attached peripherals.

Support:
- list peripherals
- find monitors
- find modems
- find speakers
- find printers
- find redstone relays
- detect Tom's Peripherals devices by type/name/methods where possible
- expose capabilities instead of raw device assumptions

Device capability examples:
{
  "display.text": true,
  "display.color": true,
  "display.bitmap": false,
  "input.keyboard": true,
  "input.mouse": true,
  "network.rednet": true,
  "redstone.extended": false,
  "watchdog": false
}

Tom's Peripherals adapter:
Create tom_adapter.lua.

This module must not break if Tom's Peripherals is not installed.
It should safely detect:
- GPU / bitmap monitor support
- keyboard support
- redstone port support
- watchdog timer support

Expose:
- isAvailable()
- getCapabilities()
- findGPU()
- findKeyboard()
- findRedstonePort()
- findWatchdog()
- setupWatchdog(timeout)
- feedWatchdog()
- shutdownWatchdog()
- normalizeInputEvent(event)

Do not assume exact peripheral names without checking peripheral.getType/name/methods.
Use defensive code.
If Tom devices are absent, return nil/false with clear reason.

Network service:
Use rednet if a modem exists.

Support:
- open modem automatically if possible
- node id
- hostname
- protocol: "dockos.v1"
- send
- broadcast
- receive loop as service
- basic message envelope:
{
  "protocol": "dockos.v1",
  "type": "ping",
  "from": <computer_id>,
  "to": <target_or_nil>,
  "time": <os.clock_or_epoch>,
  "payload": {}
}

Implement ping/pong and service discovery.
Do not build a fake internet/store yet.
Just clean backend foundations.

Shell commands:
Implement a command layer so the backend can be tested without a full GUI.

Required commands:
- dock about
- dock version
- dock help
- dock services
- dock ps
- dock devices
- dock apps
- dock app <id>
- dock run <app_id>
- dock files
- dock ls <path>
- dock mkdir <path>
- dock touch <path>
- dock cat <path>
- dock write <path> <text>
- dock rm <path>
- dock trash <path>
- dock restore <trash_id>
- dock search <query>
- dock open <path>
- dock install-local <path>
- dock uninstall <app_id>
- dock settings get <key>
- dock settings set <key> <value>
- dock test
- dock reboot
- dock shutdown

Terminal app:
Implement a minimal terminal app as a system app.
It should use shell_service and commands.
It does not need to be visually fancy.
It must be launched through the app registry, not hardcoded.

Files app:
Implement a minimal Files app as a system app.
Backend-first is enough.
It can show text list of:
- Desktop
- Documents
- Downloads
- Pictures
- Music
- Videos
- Apps
- Trash

It must use fs_service.
It must not directly call fs everywhere.

Settings app:
Implement a minimal Settings app as a system app.
It must use settings_service.
It can show system name, version, codename, current user, device capabilities, and installed apps.

UI requirement for 0.0.1:
Only minimal UI/demo is required.
Focus on backend.
But the system must be usable from terminal.

Do not create a polished fake GUI before backend is real.
The future desktop must be able to read:
- desktop folder
- app registry
- settings
- file associations
- notifications
- process list

Error handling:
Every module should return structured results where appropriate:

{
  ok = true,
  data = ...
}

or

{
  ok = false,
  error = "clear error message",
  code = "ERROR_CODE"
}

Do not use random nil returns with no explanation.

Logging:
Implement logger with:
- info
- warn
- error
- debug

Logs:
- /dock/var/log/system.log
- /dock/var/log/boot.log
- /dock/var/log/apps.log
- /dock/var/log/services.log

Keep logs readable.
Avoid huge log spam.

Security/permissions:
Add a lightweight permission model for future use.

For 0.0.1:
- permissions are declared in app.json
- app_service validates the field exists
- no strict sandbox is required yet
- create permission_service placeholder/interface if useful

Example permissions:
- fs.read
- fs.write
- fs.delete
- network.rednet
- peripheral.access
- settings.read
- settings.write
- process.spawn

Testing:
Create /dock/tests/selftest.lua.

dock test must verify:
1. Boot directories exist.
2. Default user folders exist.
3. Settings can save/load.
4. A document can be created in Documents.
5. A desktop shortcut can be created and resolved.
6. A file can be moved to Trash and restored.
7. App registry scans system apps.
8. Terminal/Files/Settings app manifests validate.
9. Device manager returns capabilities without crashing.
10. Logger writes logs.
11. Package manager rejects invalid app manifests.
12. Process manager catches a crashing process.

Acceptance criteria:
After implementation, on a fresh CC:Tweaked computer:
1. Running startup.lua boots DockOS Paralimni 0.0.1.
2. The OS creates the full directory tree.
3. dock about shows DockOS Paralimni 0.0.1.
4. dock files shows real folders, not fake categories.
5. dock write dock/users/default/Documents/test.txt hello creates a real file.
6. dock open dock/users/default/Documents/test.txt resolves an app association.
7. dock trash can move a file to Trash.
8. dock restore can restore it.
9. dock apps lists apps from manifests.
10. dock run dock.terminal launches the Terminal app through app_service.
11. dock devices works with and without Tom's Peripherals.
12. Reboot keeps user files/settings.
13. No desktop/app list is hardcoded in UI.
14. The system still works if Tom's Peripherals is absent.
15. App crashes do not crash the OS.

Coding rules:
- Lua compatible with CC:Tweaked.
- No external dependencies.
- Do not assume luasocket, lfs, bit32, or non-CC libraries.
- Use fs, os, term, window, peripheral, rednet, settings, textutils, parallel where appropriate.
- Use fs.combine for paths.
- Use pcall around app/service execution.
- Avoid global variables.
- Each module should return a table.
- Keep names consistent.
- Use English-only logs/output.
- Do not add Russian comments.
- Prefer clear functions over giant monolithic scripts.
- Do not overcomplicate with fake enterprise systems.
- Build a real small OS foundation.

Deliverables:
1. Create all required files/modules.
2. Provide a clear file tree.
3. Provide install/run instructions for CC:Tweaked.
4. Provide a short explanation of how Paralimni backend works.
5. Provide a short checklist showing acceptance criteria status.
6. Do not only give pseudocode. Implement real Lua files.
7. If something cannot be fully implemented in CC:Tweaked, create a clean interface and a safe fallback, but do not fake it in the UI.