Config = {
    Debug = false,

    ResourceName = 'oxlyn-graffiti',

    RenderDistance = 140.0,
    ChunkSize = 80.0,
    SprayDistance = 3.2,
    MaxPaintDistance = 2.4,
    LineThickness = 0.12,
    MinPointDistance = 0.05,
    InterpolationStep = 0.08,
    MaxStrokePoints = 320,
    MaxGraffitiPerPlayer = 30,
    MaxGraffitiArea = 20.0,
    SprayCooldown = 800,
    PaintUsage = 8,
    DebugTextScale = 0.32,
    SprayPropModel = `prop_cs_spray_01`,
    ClipOffset = 0.08,

    Db = {
        TableName = 'oxlyn_graffiti',
        StrokeTableName = 'oxlyn_graffiti_strokes',
    },

    Colors = {
        spraycan_black = { r = 15, g = 15, b = 15, a = 255 },
        spraycan_white = { r = 240, g = 240, b = 240, a = 255 },
        spraycan_red = { r = 210, g = 35, b = 35, a = 255 },
        spraycan_blue = { r = 30, g = 100, b = 220, a = 255 },
        spraycan_green = { r = 35, g = 180, b = 90, a = 255 },
        spraycan_purple = { r = 145, g = 80, b = 180, a = 255 },
    },

    AllowedSurfaceTypes = {
        'concrete',
        'brick',
        'stone',
        'plaster',
        'tile',
        'metal',
        'wood',
        'asphalt',
    },

    DisabledSurfaceTypes = {},

    Items = {
        SprayCan = 'spraycan',
        GraffitiRemover = 'graffiti_remover',
        ColorItems = {
            'spraycan_black',
            'spraycan_white',
            'spraycan_red',
            'spraycan_blue',
            'spraycan_green',
            'spraycan_purple'
        }
    },
}
