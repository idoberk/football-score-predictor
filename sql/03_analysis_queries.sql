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
    