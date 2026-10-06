fx_version 'cerulean'
game 'gta5'

author 'OxLyn'
description 'Freehand graffiti system for QBCore with database persistence and chunk streaming'
version '1.0.0'

shared_scripts {
  'config.lua',
  'shared/*.lua'
}

client_scripts {
  'client/*.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/*.lua'
}

lua54 'yes'
