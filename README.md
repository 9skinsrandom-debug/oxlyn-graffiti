# oxlyn-graffiti

Freehand graffiti system for QBCore and FiveM. This resource allows players to spray directly onto world surfaces using a spray can item, render all graffiti in real time, stream nearby graffiti by chunk, save them to the database, and remove them with a graffiti remover item.

Features
- Freehand painting with mouse hold
- Raycasted spray points on suitable world surfaces
- Spray can prop and animation
- Particle-like spray effect using line rendering and debug output
- Persistent graffiti saved via oxmysql
- Batch syncing and chunk-based streaming for multiplayer
- Gradual removal with `graffiti_remover`
- Configurable render distance, cooldowns, limits, and debug mode

Installation
1. Copy the resource folder into your server resources directory.
2. Add the resource to your server config:
   ensure oxlyn-graffiti
3. Import `sql/graffiti.sql` into your database.
4. Ensure `oxmysql` and `qb-core` are running.
5. Add the following items to your QBCore shared items file:
   - `spraycan_black`
   - `spraycan_white`
   - `spraycan_red`
   - `spraycan_blue`
   - `spraycan_green`
   - `spraycan_purple`
   - `graffiti_remover`

Recommended items
```lua
['spraycan_black'] = { label = 'Black Spray Can', weight = 0.5, type = 'item', image = 'spraycan_black.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'A can of black spray paint.' },
['spraycan_white'] = { label = 'White Spray Can', weight = 0.5, type = 'item', image = 'spraycan_white.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'A can of white spray paint.' },
['spraycan_red'] = { label = 'Red Spray Can', weight = 0.5, type = 'item', image = 'spraycan_red.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'A can of red spray paint.' },
['spraycan_blue'] = { label = 'Blue Spray Can', weight = 0.5, type = 'item', image = 'spraycan_blue.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'A can of blue spray paint.' },
['spraycan_green'] = { label = 'Green Spray Can', weight = 0.5, type = 'item', image = 'spraycan_green.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'A can of green spray paint.' },
['spraycan_purple'] = { label = 'Purple Spray Can', weight = 0.5, type = 'item', image = 'spraycan_purple.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'A can of purple spray paint.' },
['graffiti_remover'] = { label = 'Graffiti Remover', weight = 0.5, type = 'item', image = 'graffiti_remover.png', unique = false, useable = false, shouldClose = true, combinable = nil, description = 'Used to remove existing graffiti.' },
```

How it works
- The player uses a spray can item.
- When holding the left mouse button near a wall or suitable surface, a raycast checks the exact hit point and normal.
- Each spray movement adds a point to a local stroke.
- Strokes are interpolated and optimized before saving.
- When the player releases the mouse, the stroke is sent to the server and saved in the database.
- Existing graffiti around the player are streamed via chunk-based loading.

Notes
- This resource is intentionally designed around the QBCore inventory and oxmysql stack.
- The actual paint effect is represented as world lines with proper point interpolation and surface alignment.
- The system uses a large amount of validation on the server side to reject malformed or oversized graffiti payloads.

Configuration
The main config is in `config.lua` and includes:
- render distance
- chunk size
- spray distance
- line thickness
- spray colors
- cooldowns
- max painting limits
- database table names
- debug mode

Debug mode
Set:
```lua
Config.Debug = true
```
This will print backend info and draw the raycast hit point and normal in 3D.

Limitations
- This is a real-time freehand graffiti resource and does not use a text editor or preset image system.
- The visible paint is drawn as a line-based effect optimized for GTA V performance and network compatibility.
- Additional polish such as improved prop models or realistic particle systems can be layered later if desired.

Authoring note
This resource is designed around the request for a real-feeling spray system: the player paints on surfaces in the world with their mouse, each stroke is visually continuous, and the final artwork persists across server restarts.
