-- Privileges go to group roles, and people or apps log in with their own role that is a member of a group.
-- Each roles gets only what its job needs.
-- PUBLIC is a built in group that every role belongs to. By default, it may connect to any database,
-- so any login on this server could open ours.
-- We take that away and then give CONNECT back only to the roles that need it.
REVOKE CONNECT, TEMPORARY ON DATABASE football_predictor FROM PUBLIC;

-- Read only group for analysis and dashboard exports.
CREATE ROLE football_analyst
    NOLOGIN;

-- Pipeline group that can do everything the analyst group can, plus INSERT on specific tables.
CREATE ROLE football_pipeline
    NOLOGIN
    IN ROLE football_analyst;

CREATE ROLE analyst_user
    LOGIN
    IN ROLE football_analyst;

CREATE ROLE pipeline_app
    LOGIN
    IN ROLE football_pipeline;

GRANT CONNECT ON DATABASE football_predictor TO football_analyst;

GRANT USAGE ON SCHEMA public TO football_analyst;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO football_analyst;

ALTER DEFAULT PRIVILEGES FOR ROLE football_admin IN SCHEMA public
    GRANT SELECT ON TABLES TO football_analyst;

-- Check what each login role may do.
-- has_*_privilege() returns whether the current role can do X, without actually trying it, so it is safe.
SELECT
    r.role_name,
    has_database_privilege(r.role_name, 'football_predictor', 'CONNECT') AS can_connect,
    has_table_privilege(r.role_name, 'matches', 'SELECT') AS select_matches,
    has_table_privilege(r.role_name, 'teams', 'INSERT') AS insert_teams,
    has_table_privilege(r.role_name, 'matches', 'DELETE') AS delete_matches,
    has_table_privilege(r.role_name, 'matches', 'TRUNCATE') AS truncate_matches,
    has_schema_privilege(r.role_name, 'public', 'CREATE') AS create_tables
FROM (
    VALUES ('analyst_user'), ('pipeline_app'), ('football_admin')
) AS r (role_name);