CREATE TABLE IF NOT EXISTS eventstore.events2 (
    instance_id TEXT NOT NULL
    , aggregate_type TEXT NOT NULL
    , aggregate_id TEXT NOT NULL
    
    , event_type TEXT NOT NULL
    , "sequence" BIGINT NOT NULL
    , revision SMALLINT NOT NULL
    , created_at TIMESTAMPTZ NOT NULL
    , payload JSONB
    , creator TEXT NOT NULL
    , "owner" TEXT NOT NULL
    
    , "position" DECIMAL NOT NULL
    , in_tx_order INTEGER NOT NULL

    , PRIMARY KEY (instance_id, aggregate_type, aggregate_id, "sequence")
	, INDEX es_active_instances (created_at DESC) STORING ("position")
    , INDEX es_wm (aggregate_id, instance_id, aggregate_type, event_type)
    , INDEX es_projection (instance_id, aggregate_type, event_type, "position" DESC)
);

-- represents an event to be created.
CREATE TYPE IF NOT EXISTS eventstore.command AS (
    instance_id TEXT
    , aggregate_type TEXT
    , aggregate_id TEXT
    , command_type TEXT
    , revision INT2
    , payload JSONB
    , creator TEXT
    , owner TEXT
);

-- index is used for filtering for the current sequence of the aggregate
CREATE INDEX IF NOT EXISTS e_push_idx ON eventstore.events2(instance_id, aggregate_type, aggregate_id, "owner", "sequence" DESC);

CREATE OR REPLACE FUNCTION eventstore.commands_to_events(commands eventstore.command[]) RETURNS SETOF eventstore.events2 VOLATILE AS $$
SELECT
    ("c").instance_id
    , ("c").aggregate_type
    , ("c").aggregate_id
    , ("c").command_type AS event_type
    , cs.sequence + ROW_NUMBER() OVER (PARTITION BY ("c").instance_id, ("c").aggregate_type, ("c").aggregate_id) AS sequence
    , ("c").revision
    , hlc_to_timestamp(cluster_logical_timestamp()) AS created_at
    , ("c").payload
    , ("c").creator
    , cs.owner
    , cluster_logical_timestamp() AS position
    , ROW_NUMBER() OVER () AS in_tx_order   
FROM 
    UNNEST(commands) AS "c"
JOIN (
    SELECT
        cmds.instance_id
        , cmds.aggregate_type
        , cmds.aggregate_id
        , CASE WHEN (e.owner <> '') THEN e.owner ELSE cmds.owner END AS owner
        , COALESCE(MAX(e.sequence), 0) AS sequence
    FROM (
        SELECT DISTINCT
            ("cmds").instance_id
            , ("cmds").aggregate_type
            , ("cmds").aggregate_id
            , ("cmds").owner
        FROM UNNEST(commands) AS "cmds"
    ) AS cmds
    LEFT JOIN eventstore.events2 AS e
        ON cmds.instance_id = e.instance_id
        AND cmds.aggregate_type = e.aggregate_type
        AND cmds.aggregate_id = e.aggregate_id
        AND (cmds.owner = '' OR cmds.owner = e.owner)
    GROUP BY
        cmds.instance_id
        , cmds.aggregate_type
        , cmds.aggregate_id
        , 4 -- owner
) AS cs
    ON ("c").instance_id = cs.instance_id
    AND ("c").aggregate_type = cs.aggregate_type
    AND ("c").aggregate_id = cs.aggregate_id
    AND (("c").owner = '' OR cs.owner = ("c").owner)
ORDER BY
    in_tx_order
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION eventstore.push(commands eventstore.command[]) RETURNS SETOF eventstore.events2 AS $$
    INSERT INTO eventstore.events2
    SELECT * FROM eventstore.commands_to_events(commands)
    RETURNING *
$$ LANGUAGE SQL;