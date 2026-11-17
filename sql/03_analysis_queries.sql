-- 1. League table:
-- Final standings for one season and division, computed from the match results.
-- Change the WHERE line to see another season (e.g 2019, 'SP2').
-- These are end of season totals, so they include matches after any given date.
WITH team_matches AS (
    -- Each match seen from both sides, so the home team's goals are "for" in the
    -- first half of the query (before the UNION ALL clause), and "against" in the
    -- second half of the query (after the UNION ALL clause).
    SELECT
        season_start,
        division_code,
        home_team_id AS team_id,
        ft_home_goals AS goals_for,
        ft_away_goals AS goals_against
    FROM matches
    UNION ALL
    SELECT
        season_start,
        division_code,
        away_team_id,
        ft_away_goals,
        ft_home_goals
    FROM matches
),

team_seasons AS (
    -- One row per team per season
    SELECT
        season_start,
        division_code,
        team_id,
        COUNT(*) AS played,
        COUNT(*) FILTER (WHERE goals_for > goals_against) AS won,
        COUNT(*) FILTER (WHERE goals_for = goals_against) AS drawn,
        COUNT(*) FILTER (WHERE goals_for < goals_against) AS lost,
        SUM(goals_for) AS goals_for,
        SUM(goals_against) AS goals_against,
        SUM(
            CASE
                WHEN goals_for > goals_against THEN 3
                WHEN goals_for = goals_against THEN 1
                ELSE 0
            END
        ) AS points
    FROM team_matches
    GROUP BY
        season_start,
        division_code,
        team_id
)

SELECT
    s.season_label,
    ts.division_code,
    -- Rank each team within its own season and division without collapsing the rows.
    -- In La Liga, tiebreak is determined by head to head, but we want to simplify it so
    -- instead we will determine the tiebreak by goal difference and then goals scored.
    RANK() OVER (
        PARTITION BY ts.season_start, ts.division_code
        ORDER BY
            ts.points DESC,
            ts.goals_for - ts.goals_against DESC,
            ts.goals_for DESC
    ) AS position,
    t.team_name,
    ts.played,
    ts.won,
    ts.drawn,
    ts.lost,
    ts.goals_for,
    ts.goals_against,
    ts.goals_for - ts.goals_against AS goal_difference,
    ts.points
FROM team_seasons AS ts
JOIN teams AS t ON t.team_id = ts.team_id
JOIN seasons AS s ON ts.season_start = s.season_start
WHERE ts.season_start = 2025 AND ts.division_code = 'SP1'
ORDER BY position, t.team_name;


-- 2. Rolling shots on target:
-- The model's feature (shot change quality since we don't have xG data available), computed in SQL.
-- Take the average shots on target for and against for each team and match over the team's previous 10 matches.
-- Only matches BEFORE this one count (avoids leakage).
-- Only La Liga values count, but Segunda matches still take place in the window.
-- At least 5 values, otherwise NULL.
WITH team_matches AS (
    -- One row per team per match.
    SELECT
        m.match_date,
        m.division_code,
        m.home_team_id AS team_id,
        m.away_team_id AS opponent_id,
        'H' AS venue,
        ms.home_shots_on_target AS target_for,
        ms.away_shots_on_target AS target_against
    FROM matches AS m
    LEFT JOIN match_stats AS ms ON m.match_id = ms.match_id
    UNION ALL
    SELECT
        m.match_date,
        m.division_code,
        m.away_team_id,
        m.home_team_id,
        'A',
        ms.away_shots_on_target,
        ms.home_shots_on_target
    FROM matches AS m
    LEFT JOIN match_stats AS ms ON m.match_id = ms.match_id
),

la_liga_values AS (
    -- All column of team_matches, plus copies of the stats that are NULL outside La Liga.
    -- CASE without ELSE returns NULL.
    SELECT
        *,
        CASE WHEN division_code = 'SP1' THEN target_for END AS la_liga_target_for,
        CASE WHEN division_code = 'SP1' THEN target_against END AS la_liga_target_against
    FROM team_matches
),

rolling AS (
    -- AVG skips NULLs, and COUNT(column) counts only non-NULL values.
    SELECT
        match_date,
        division_code,
        team_id,
        opponent_id,
        venue,
        target_for,
        target_against,
        CASE
            WHEN COUNT(la_liga_target_for) OVER previous_10 >= 5
                THEN ROUND(AVG(la_liga_target_for) OVER previous_10, 2)
        END AS target_for_avg10,
        CASE
            WHEN COUNT(la_liga_target_against) OVER previous_10 >= 5
                THEN ROUND(AVG(la_liga_target_against) OVER previous_10, 2)
        END AS target_against_avg10
    FROM la_liga_values
    WINDOW previous_10 AS (
        PARTITION BY team_id
        ORDER BY match_date
        ROWS BETWEEN 10 PRECEDING AND 1 PRECEDING
    )
)

SELECT
    r.match_date,
    r.venue,
    o.team_name AS opponent,
    r.target_for,
    r.target_against,
    r.target_for_avg10,
    r.target_against_avg10
FROM rolling AS r
JOIN teams AS t ON r.team_id = t.team_id
JOIN teams AS o ON r.opponent_id = o.team_id
WHERE t.team_name = 'Real Madrid'
ORDER BY r.match_date DESC
LIMIT 5;
