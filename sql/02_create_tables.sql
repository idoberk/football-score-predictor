-- Creates the project tables.
-- Tables are created in foreign key order: A table can only point to tables that already exist.

-- Lookup table for the two Spanish divisions in the data
CREATE TABLE divisions (
    division_code CHAR(3) PRIMARY KEY, -- Dataset code: 'SP1' or 'SP2'
    division_name TEXT NOT NULL UNIQUE,
    tier SMALLINT NOT NULL UNIQUE CHECK (tier > 0) -- 1 = La Liga, 2 = Segunda
);

-- One row per season in the data (2006/07 is missing, so no row)
CREATE TABLE seasons (
    season_start SMALLINT PRIMARY KEY, -- Same value as SeasonStart, e.g 2025
    season_label CHAR(7) NOT NULL UNIQUE, -- e.g '2025/26'
    start_date DATE NOT NULL UNIQUE, -- The 10 August cutoff used for SeasonStart
    -- A name constraint. The error message says exactly which rule failed
    CONSTRAINT seasons_start_date_in_start_year
        CHECK (EXTRACT(YEAR FROM start_date) = season_start)
);

-- One row per club, with team_id as primary key so a club's name lives in exactly one place
CREATE TABLE teams (
    team_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    team_name TEXT NOT NULL UNIQUE
);

-- One row per played match: Before kickoff data (Elo, form) and the result.
-- Match stats and odds live in their own tables
CREATE TABLE matches (
    match_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    division_code CHAR(3) NOT NULL REFERENCES divisions (division_code),
    -- Stored on purpose (it could be derived from match_date),
    -- so filtering by season is a plain join
    season_start SMALLINT NOT NULL REFERENCES seasons (season_start),
    match_date DATE NOT NULL,
    home_team_id INTEGER NOT NULL REFERENCES teams (team_id),
    away_team_id INTEGER NOT NULL REFERENCES teams (team_id),
    -- Before kickoff values. NULL allowed because Elo is missing for a few hundred matches
    home_elo NUMERIC(6, 2),
    away_elo NUMERIC(6, 2),
    form3_home SMALLINT,
    form5_home SMALLINT,
    form3_away SMALLINT,
    form5_away SMALLINT,
    -- Result
    ft_home_goals SMALLINT NOT NULL CHECK (ft_home_goals >= 0),
    ft_away_goals SMALLINT NOT NULL CHECK (ft_away_goals >= 0),
    ft_result CHAR(1) NOT NULL,
    ht_home_goals SMALLINT CHECK (ht_home_goals >= 0),
    ht_away_goals SMALLINT CHECK (ht_away_goals >= 0),
    ht_result CHAR(1),
    CONSTRAINT matches_different_teams
        CHECK (home_team_id <> away_team_id),
    -- The result letter must agree with the score. This also limits ft_result to
    -- 'H', 'D' or 'A', so no separate IN check is needed
    CONSTRAINT matches_ft_result_agrees_with_goals
        CHECK (
            ft_result = CASE
                WHEN ft_home_goals > ft_away_goals THEN 'H'
                WHEN ft_home_goals = ft_away_goals THEN 'D'
                ELSE 'A'
            END
        ),
    -- Same rule at half time. When the half time score is missing (NULL), the check
    -- evaluates to NULL, and Postgres only rejects a row when a check is FALSE
    CONSTRAINT matches_ht_result_agrees_with_goals
        CHECK (
            ht_result = CASE
                WHEN ht_home_goals > ht_away_goals THEN 'H'
                WHEN ht_home_goals = ht_away_goals THEN 'D'
                ELSE 'A'
            END
        ),
    CONSTRAINT matches_ht_goals_not_above_ft
        CHECK (ht_home_goals <= ft_home_goals AND ht_away_goals <= ft_away_goals),
    -- Natural keys (both verified with 0 duplicates in the data): Each pairing
    -- happens once per season, and a team plays at most one home match per day
    CONSTRAINT matches_one_pairing_per_season
        UNIQUE (season_start, division_code, home_team_id, away_team_id),
    CONSTRAINT matches_one_home_match_per_day
        UNIQUE (match_date, home_team_id)
);

-- Match stats: One row per match that has stats (8,610 older matches have none,
-- so they get no row here). These are outcomes of the match: The model only uses
-- them as rolling averages over previous matches.
-- No "shots on target <= shots" check: One source row breaks it (SP2 2024/25,
-- Huesca vs Burgos, away 5 shots, 7 on target)
CREATE TABLE match_stats (
    -- Primary key AND foreign key: At most one stats row per match (a 1:1 link).
    -- ON DELETE CASCADE: If a match is deleted, its stats go with it
    match_id INTEGER PRIMARY KEY REFERENCES matches (match_id) ON DELETE CASCADE,
    home_shots SMALLINT NOT NULL CHECK (home_shots >= 0),
    away_shots SMALLINT NOT NULL CHECK (away_shots >= 0),
    home_shots_on_target SMALLINT NOT NULL CHECK (home_shots_on_target >= 0),
    away_shots_on_target SMALLINT NOT NULL CHECK (away_shots_on_target >= 0),
    home_fouls SMALLINT NOT NULL CHECK (home_fouls >= 0),
    away_fouls SMALLINT NOT NULL CHECK (away_fouls >= 0),
    home_corners SMALLINT NOT NULL CHECK (home_corners >= 0),
    away_corners SMALLINT NOT NULL CHECK (away_corners >= 0),
    home_yellow_cards SMALLINT NOT NULL CHECK (home_yellow_cards >= 0),
    away_yellow_cards SMALLINT NOT NULL CHECK (away_yellow_cards >= 0),
    home_red_cards SMALLINT NOT NULL CHECK (home_red_cards >= 0),
    away_red_cards SMALLINT NOT NULL CHECK (away_red_cards >= 0)
);

-- Bookmaker odds (1X2 only): The benchmark for the model, never a feature.
-- Bet365 and the market maximum each come as a full set of three or not at all
CREATE TABLE match_odds (
    match_id INTEGER PRIMARY KEY REFERENCES matches (match_id) ON DELETE CASCADE,
    -- Decimal odds are always above 1 (a stake of 1 returns more than 1)
    b365_home NUMERIC(5, 2) CHECK (b365_home > 1),
    b365_draw NUMERIC(5, 2) CHECK (b365_draw > 1),
    b365_away NUMERIC(5, 2) CHECK (b365_away > 1),
    max_home NUMERIC(5, 2) CHECK (max_home > 1),
    max_draw NUMERIC(5, 2) CHECK (max_draw > 1),
    max_away NUMERIC(5, 2) CHECK (max_away > 1),
    -- num_nonnulls counts the arguments that are not NULL: A row must hold at
    -- least one set of odds, otherwise it should not exist
    CONSTRAINT match_odds_not_empty
        CHECK (num_nonnulls(b365_home, max_home) > 0)
);

-- Elo history of our teams (Spanish clubs only), about two ratings per month.
-- Needed for the latest rating before an upcoming fixture
CREATE TABLE elo_ratings (
    team_id INTEGER NOT NULL REFERENCES teams (team_id),
    rating_date DATE NOT NULL,
    elo NUMERIC(6, 2) NOT NULL,
    -- Composite primary key: One rating per team per date. Neither column is unique
    -- on its own
    PRIMARY KEY (team_id, rating_date)
);