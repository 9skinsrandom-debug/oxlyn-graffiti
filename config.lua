Config = {
    Debug = false,
    ResourceName = "oxlyn-graffiti",

    RenderDistance = 130.0,
    ChunkSize = 80.0,
    SprayDistance = 2.8,
    MaxPaintDistance = 2.4,
    LineThickness = 0.1,
    LineMinDistance = 0.05,
    InterpolationStep = 0.08,
    ClientBatchInterval = 650,
    DebugTextScale = 0.35,

    SprayCooldown = 1000,
    PaintColorConsumption = 12,
    MaxStrokePoints = 360,
    MaxStrokesPerGraffiti = 10,
    MaxGraffitiPerPlayer = 35,
    MaxGraffitiArea = 18.0,
    MaxGraffitiPerChunk = 250,
    ClipOffset = 0.06,
    RemovalProgress = 2200,

    Db = {
        TableName = "oxlyn_graffiti",
        StrokeTableName = "oxlyn_graffiti_strokes",
        UseQueue = true,
    },

    Colors = {
        spraycan_black = { label = "Black", r = 15, g = 15, b = 15, a = 255 },
        spraycan_white = { label = "White", r = 240, g = 240, b = 240, a = 255 },
        spraycan_red = { label = "Red", r = 210, g = 30, b = 30, a = 255 },
        spraycan_blue = { label = "Blue", r = 28, g = 96, b = 220, a = 255 },
        spraycan_green = { label = "Green", r = 35, g = 175, b = 90, a = 255 },
        spraycan_purple = { label = "Purple", r = 150, g = 75, b = 190, a = 255 },
    },

    AllowedSurfaceTypes = {
        "concrete",
        "brick",
        "plaster",
        "tile",
        "stone",
        "metal",
        "wood",
        "asphalt",
    },

    DisabledSurfaceTypes = {},

    Items = {
        SprayCan = "spraycan",
        Removal = "graffiti_remover",
    },
}
