-- Analysis queries on the fixtures table (football-data.org API).
-- Runs in the football_predictor database, with any user with a SELECT privilege.

-- 1. The next 10 fixtures, with kickoff in Madrid time.
-- teams is joined twice, once per side.
-- AT TIME ZONE turns the stored time into Madrid's local time.
-- SCHEDULED matches only have their date set, so time_confirmed is false for them.
SELECT
    f.matchday,
    f.kickoff_at AT TIME ZONE 'Europe/Madrid' AS kickoff_madrid,
    f.status = 'TIMED' AS time_confirmed,
    home.team_name AS home_team,
    away.team_name AS away_team
FROM fixtures f
JOIN teams AS home ON f.home_team_id = home.team_id
JOIN teams AS away ON f.away_team_id = away.team_id
WHERE f.status IN ('SCHEDULED', 'TIMED') AND f.kickoff_at > now()
ORDER BY f.kickoff_at, home.team_name
LIMIT 10;


-- 2. The API's finished matches compared with the matches table (the dataset).
SELECT
    CASE
        WHEN m.match_id IS NULL THEN 'Missing from matches'
        WHEN m.ft_home_goals = f.ft_home_goals AND m.ft_away_goals = f.ft_away_goals THEN 'Same score'
        ELSE 'Different score'
    END AS comparison,
    COUNT(*) AS finished_fixtures,
    MIN(f.kickoff_at AT TIME ZONE 'Europe/Madrid')::DATE AS first_match,
    MAX(f.kickoff_at AT TIME ZONE 'Europe/Madrid')::DATE AS last_match
FROM fixtures AS f
LEFT JOIN matches AS m
    ON m.season_start = f.season_start
    AND m.division_code = f.division_code
    AND m.home_team_id = f.home_team_id
    AND m.away_team_id = f.away_team_id
WHERE f.status = 'FINISHED'
GROUP BY comparison
ORDER BY first_match;