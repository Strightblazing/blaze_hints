-- blaze_hints: run once (the resource also creates these tables on start if they are missing)

CREATE TABLE IF NOT EXISTS `blaze_hints_hunts` (
    `id`         INT          NOT NULL AUTO_INCREMENT,
    `name`       VARCHAR(100) NOT NULL,
    `enabled`    TINYINT(1)   NOT NULL DEFAULT 1,
    `data`       LONGTEXT     NOT NULL,            -- JSON: { "autoStart": true, "steps": [ ... ordered steps ... ] }
    `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `blaze_hints_progress` (
    `citizenid`      VARCHAR(50)  NOT NULL,
    `hunt_id`        INT          NOT NULL,
    `step_index`     INT          NOT NULL DEFAULT 1,
    `code`           VARCHAR(255) NULL DEFAULT NULL, -- server only, never sent to clients
    `pieces_found`   TEXT         NULL,              -- JSON list of step indexes whose piece was found
    `wrong_tries`    INT          NOT NULL DEFAULT 0,
    `cooldown_until` INT          NOT NULL DEFAULT 0, -- unix time
    `completed`      TINYINT(1)   NOT NULL DEFAULT 0,
    `unlocked_stash` TINYINT(4)   NOT NULL DEFAULT 0, -- 0 locked, 1 unlocked, 2 reward box emptied
    `step_started`   INT          NOT NULL DEFAULT 0, -- unix time the current step started (timer locks)
    PRIMARY KEY (`citizenid`, `hunt_id`),
    KEY `hunt_id` (`hunt_id`),
    CONSTRAINT `blaze_hints_progress_hunt` FOREIGN KEY (`hunt_id`) REFERENCES `blaze_hints_hunts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
