# oxlyn-graffiti

Freehand graffiti system for QBCore and FiveM.

Features
- spray can item usage
- real-time freehand drawing with LMB and wall raycast
- support for multiple color spray cans
- world-space spray line interpolation for smooth curves
- database persistence with oxmysql
- distance-based chunk streaming for nearby graffiti
- removal item support with `graffiti_remover`
- configurable render distance and debug output

Installation
1. Place the folder into your `resources` directory.
2. Add to your server config:
   `ensure oxlyn-graffiti`
3. Import `sql/graffiti.sql` to your database.
4. Ensure `qb-core` and `oxmysql` are running.
5. Add items to your shared items list.

Recommended items
```lua
['spraycan'] = {
    name = 'spraycan',
    label = 'Spray Can',
    weight = 0.5,
    type = 'item',
    image = 'spraycan.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'A generic spray can.'
},
['spraycan_black'] = {
    name = 'spraycan_black',
    label = 'Black Spray Can',
    weight = 0.5,
    type = 'item',
    image = 'spraycan_black.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Black spray paint.'
},
['spraycan_white'] = {
    name = 'spraycan_white',
    label = 'White Spray Can',
    weight = 0.5,
    type = 'item',
    image = 'spraycan_white.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'White spray paint.'
},
['spraycan_red'] = {
    name = 'spraycan_red',
    label = 'Red Spray Can',
    weight = 0.5,
    type = 'item',
    image = 'spraycan_red.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Red spray paint.'
},
['spraycan_blue'] = {
    name = 'spraycan_blue',
    label = 'Blue Spray Can',
    weight = 0.5,
    type = 'item',
    image = 'spraycan_blue.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Blue spray paint.'
},
['spraycan_green'] = {
    name = 'spraycan_green',
    label = 'Green Spray Can',
    weight = 0.5,
    type = 'item',
    image = 'spraycan_green.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Green spray paint.'
},
['spraycan_purple'] = {
    name = 'spraycan_purple',
    label = 'Purple Spray Can',
    weight = 0.5,
    type = 'item',
    image = 'spraycan_purple.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Purple spray paint.'
},
['graffiti_remover'] = {
    name = 'graffiti_remover',
    label = 'Graffiti Remover',
    weight = 0.5,
    type = 'item',
    image = 'graffiti_remover.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Removes nearby graffiti.'
}
```

How the paint system works
- Hold left mouse button while aiming at a wall or suitable surface.
- A raycast checks the exact hit point and surface normal.
- Each movement adds a point to an interpolated stroke.
- Releasing the mouse sends the stroke to the server.
- The server validates the data and writes it to the database.
- Nearby graffiti are synced by chunk and render distance.

Configuration
You can adjust the main variables in `config.lua`:
- `RenderDistance`
- `ChunkSize`
- `SprayDistance`
- `MaxPaintDistance`
- `LineThickness`
- `MinPointDistance`
- `MaxStrokePoints`
- `MaxGraffitiPerPlayer`
- `MaxGraffitiArea`
- `Debug`

Debug mode
```lua
Config.Debug = true
```
This will draw the raycast hit point and normal for troubleshooting.

Notes
- This resource uses a realistic paint line approach rather than a text-to-sign generator.
- The visual effect is a world-space line drawn between interpolated points and optimized for network use.
- All graffiti are stored in the database and streamed only around the player.
