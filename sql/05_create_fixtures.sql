-- Creates the fixtures table for the football-data.org API matches, and lets the pipeline role write to it.
-- Runs after 01, 02 and 04 SQL files, as the football_admin user.

-- One row per API match, holding its latest state. Each notebook run updates the rows in place.
-- The history of changes is kept in the raw JSON files.
CREATE TABLE fixtures (
    fixture_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    api_match_id INTEGER NOT NULL UNIQUE,
    season_start SMALLINT NOT NULL REFERENCES seasons (season_start),
    division_code CHAR(3) NOT NULL REFERENCES divisions (division_code),
    matchday SMALLINT NOT NULL CHECK (matchday BETWEEN 1 AND 38),
    -- For SCHEDULED matches, only the date is real. The API shows the time as 00:00 UTC until it is set
    kickoff_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(10) NOT NULL,
    home_team_id INTEGER NOT NULL REFERENCES teams (team_id),
    away_team_id INTEGER NOT NULL REFERENCES teams (team_id),
    -- NULL until the match is decided
    ft_home_goals SMALLINT CHECK (ft_home_goals >= 0),
    ft_away_goals SMALLINT CHECK (ft_away_goals >= 0),
    ft_result CHAR(1) GENERATED ALWAYS AS (
        CASE
            WHEN ft_home_goals > ft_away_goals THEN 'H'
            WHEN ft_home_goals = ft_away_goals THEN 'D'
            WHEN ft_home_goals < ft_away_goals THEN 'A'
        END
    ) STORED,
    api_last_updated TIMESTAMPTZ NOT NULL, -- The API's lastUpdated for this match
    fetched_at TIMESTAMPTZ NOT NULL, -- When the API was called
    raw JSONB NOT NULL,
    CONSTRAINT fixtures_valid_status
        CHECK (
            status IN (
                'SCHEDULED', 'TIMED', 'IN_PLAY', 'PAUSED', 'FINISHED',
                'SUSPENDED', 'POSTPONED', 'CANCELLED', 'AWARDED'
            )
        ),
    CONSTRAINT fixtures_different_teams
        CHECK (home_team_id <> away_team_id),
    -- Goals only for a decided match. The API sends a 0-0 placeholder for a cancelled match
    CONSTRAINT fixtures_goals_only_when_decided
        CHECK (
            status IN ('FINISHED', 'AWARDED')
            OR (ft_home_goals IS NULL AND ft_away_goals IS NULL)
        ),
    CONSTRAINT fixtures_both_goals_or_none
        CHECK (num_nulls(ft_home_goals, ft_away_goals) IN (0, 2)),
    CONSTRAINT fixtures_one_pairing_per_season
        UNIQUE (season_start, division_code, home_team_id, away_team_id)
);

GRANT INSERT, UPDATE ON fixtures TO football_pipeline;