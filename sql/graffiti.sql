CREATE TABLE IF NOT EXISTS `oxlyn_graffiti` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `author` VARCHAR(96) NOT NULL DEFAULT 'Unknown',
    `author_id` INT NOT NULL DEFAULT 0,
    `color` VARCHAR(32) NOT NULL DEFAULT 'spraycan_black',
    `thickness` FLOAT NOT NULL DEFAULT 0.1,
    `x_pos` FLOAT NOT NULL DEFAULT 0,
    `y_pos` FLOAT NOT NULL DEFAULT 0,
    `z_pos` FLOAT NOT NULL DEFAULT 0,
    `chunk_key` VARCHAR(64) NOT NULL DEFAULT '0:0',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_chunk` (`chunk_key`),
    KEY `idx_author` (`author_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `oxlyn_graffiti_strokes` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `graffiti_id` INT NOT NULL,
    `stroke_index` INT NOT NULL DEFAULT 0,
    `points` LONGTEXT NOT NULL,
    `surface_normal` LONGTEXT NOT NULL,
    `thickness` FLOAT NOT NULL DEFAULT 0.1,
    `color` VARCHAR(32) NOT NULL DEFAULT 'spraycan_black',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_graffiti` (`graffiti_id`),
    CONSTRAINT `fk_graffiti_strokes` FOREIGN KEY (`graffiti_id`) REFERENCES `oxlyn_graffiti` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
