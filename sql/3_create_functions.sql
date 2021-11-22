-- Check if the Bander is present and active
DROP FUNCTION IF EXISTS ro_is_active_bander;

CREATE FUNCTION ro_is_active_bander(b_id uuid) RETURNS boolean AS $$
DECLARE
  test_state enum_bander_state := NULL;
BEGIN
    SELECT bander_state INTO test_state 
    FROM bander 
    WHERE bander.id = b_id;

    IF test_state = 'ACTIVE'::enum_bander_state THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Check if the Bander is present and suspended
DROP FUNCTION IF EXISTS ro_is_suspended_bander;

CREATE FUNCTION ro_is_suspended_bander(b_id uuid) RETURNS boolean AS $$
DECLARE
  test_state enum_bander_state := NULL;
BEGIN
    SELECT bander_state INTO test_state 
    FROM bander 
    WHERE bander.id = b_id;

    IF test_state = 'SUSPENDED'::enum_bander_state THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_project_bander_member_count;
--count number of members in project
CREATE FUNCTION ro_project_bander_member_count(p_id uuid) 
RETURNS int AS $$ 

BEGIN
    RETURN (SELECT COUNT (bander_id) FROM project_bander_membership WHERE project_id = p_id);
END
$$
LANGUAGE PLPGSQL;

--######## GET PROJECT DETAIL####
--get all fields from project table for p_id
--count number of members in project
--count number of event records for a project 

DROP FUNCTION IF EXISTS ro_project_detail(p_id uuid);

CREATE FUNCTION ro_project_detail(p_id uuid)
RETURNS TABLE (
  id uuid,
  row_creation_timestamp_ timestamp with time zone,
  row_creation_user_ text,
  row_update_timestamp_ timestamp with time zone,
  row_update_user_ text,
  row_creation_idx integer,
  name text,
  project_state enum_project_state,
  description text,
  default_moratorium_expiry timestamp with time zone,
  organisation text,
  coordinator_id uuid,
  is_doc_project boolean,
  location text,
  permit_id text,
  permit_expiry timestamp with time zone,
  project_manager text,
  num_project_members integer,
  num_event_records integer

 ) AS $$
BEGIN
    RETURN QUERY 
    SELECT p.*, b.person_name, count(pbm.bander_id)::integer,(select count(e.id) from event AS e where p_id = e.project_id)::integer AS project_event_count
    FROM project AS p
	INNER JOIN bander AS b ON p.coordinator_id = b.id
	LEFT JOIN project_bander_membership AS pbm ON p.id = pbm.project_id
	WHERE p.id = p_id
	GROUP BY p.id, b.person_name;

END; $$
LANGUAGE PLPGSQL;

-- Check if the Project is present
DROP FUNCTION IF EXISTS ro_is_project;

CREATE FUNCTION ro_is_project(p_id uuid) RETURNS boolean AS $$
DECLARE
  matching_project_count NUMERIC := 0;
BEGIN
    SELECT count(project.id) INTO matching_project_count 
    FROM project 
    WHERE project.id = p_id;

    IF matching_project_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Check if the Project is present and active
DROP FUNCTION IF EXISTS ro_is_active_project;

CREATE FUNCTION ro_is_active_project(p_id uuid) RETURNS boolean AS $$
DECLARE
  test_state enum_project_state := NULL;
BEGIN
    SELECT project_state INTO test_state 
    FROM project 
    WHERE project.id = p_id;

    IF test_state = 'ACTIVE'::enum_project_state THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- is project name unique

DROP FUNCTION IF EXISTS ro_is_project_name_unique(p_name text);

CREATE FUNCTION ro_is_project_name_unique(p_name text)
RETURNS boolean
  AS $$

DECLARE
 matching_project_count NUMERIC := 0;
BEGIN
    SELECT COUNT(project.name) INTO matching_project_count
    FROM project
    WHERE project.name = p_name;

    IF matching_project_count > 0 THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;   $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_is_project_name_different(p_id uuid, p_name text);

CREATE FUNCTION ro_is_project_name_different(p_id uuid, p_name text)
RETURNS boolean
  AS $$

DECLARE
 matching_project_count NUMERIC := 0;
BEGIN
    SELECT COUNT(project.name) INTO matching_project_count
    FROM project
    WHERE project.name = p_name AND project.id = p_id;

    IF matching_project_count > 0 THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;   $$
LANGUAGE PLPGSQL;


-- Return the IDs of all the projects for which this bander is a member
DROP FUNCTION IF EXISTS ro_bander_project_list;

CREATE FUNCTION ro_bander_project_list(b_id uuid) 
RETURNS SETOF uuid AS $$
BEGIN
    RETURN QUERY 
      WITH 
      project_list AS
      (
        SELECT project_id 
        FROM project_bander_membership 
        WHERE bander_id = b_id AND is_deleted = false
        UNION
        SELECT id as project_id 
        FROM project 
        WHERE coordinator_id = b_id
      )
      SELECT DISTINCT project_id FROM project_list;
END
$$
LANGUAGE PLPGSQL;


-- Return the IDs of all the projects for which this bander is/was a member
DROP FUNCTION IF EXISTS ro_bander_full_project_history;

CREATE FUNCTION ro_bander_full_project_history(b_id uuid) 
RETURNS SETOF uuid AS $$
BEGIN
    RETURN QUERY 
      WITH 
      project_list AS
      (
        SELECT project_id 
        FROM project_bander_membership 
        WHERE bander_id = b_id
        UNION
        SELECT id as project_id 
        FROM project 
        WHERE coordinator_id = b_id
      )
      SELECT DISTINCT project_id FROM project_list;
END
$$
LANGUAGE PLPGSQL;


-- Return the IDs of all the birds for which this bander has a record
DROP FUNCTION IF EXISTS ro_bander_bird_list;

CREATE FUNCTION ro_bander_bird_list(b_id uuid) 
RETURNS TABLE (
  id uuid)
AS $$
BEGIN
    RETURN QUERY 
      SELECT DISTINCT bird_id FROM event where event_reporter_id = b_id OR event_provider_id = b_id OR event_owner_id = b_id;
END
$$
LANGUAGE PLPGSQL;

-- Return the IDs of all the banders which are members of a project
DROP FUNCTION IF EXISTS ro_project_bander_list;

CREATE FUNCTION ro_project_bander_list(p_id uuid) 
RETURNS SETOF uuid AS $$
BEGIN
    RETURN QUERY SELECT bander_id FROM project_bander_membership WHERE project_id = p_id;
END
$$
LANGUAGE PLPGSQL;

-- Return the details of all the banders which are members of a project
DROP FUNCTION IF EXISTS ro_project_bander_details;

CREATE FUNCTION ro_project_bander_details(p_id uuid) 
RETURNS TABLE (
  id uuid,
  nznbbs_certification_number text,
  is_hidden boolean,
  bander_state enum_bander_state,
  primary_organisation text
) AS $$
BEGIN
    RETURN QUERY 
    SELECT b.id, b.nznbbs_certification_number, b.is_hidden, b.bander_state, b.primary_organisation
    FROM bander b 
    INNER JOIN project_bander_membership memb ON b.id = memb.bander_id AND memb.project_id = p_id;
END
$$
LANGUAGE PLPGSQL;

-- Retruns a boolean indicating whether a bander is part of a project
DROP FUNCTION IF EXISTS ro_bander_is_in_project;

CREATE FUNCTION ro_bander_is_in_project(b_id uuid, p_id uuid) RETURNS BOOLEAN AS $$
DECLARE
  matching_project_count NUMERIC := 0;  
BEGIN
    -- Check if the passed project is present
    SELECT COUNT(projs.project_id) INTO matching_project_count
    FROM (SELECT ro_bander_project_list(b_id) AS project_id) AS projs
    WHERE projs.project_id = p_id;

    -- Return happiness or otherwise
    IF matching_project_count > 0 THEN
        RETURN TRUE;
    END IF;    

    -- Default is no match
    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Retruns a boolean indicating whether a bander is part of a project
DROP FUNCTION IF EXISTS ro_bander_ever_in_project;

CREATE FUNCTION ro_bander_ever_in_project(b_id uuid, p_id uuid) RETURNS BOOLEAN AS $$
DECLARE
  matching_project_count NUMERIC := 0;  
BEGIN
    -- Check if the passed project is present
    SELECT COUNT(projs.project_id) INTO matching_project_count
    FROM (SELECT ro_bander_full_project_history(b_id) AS project_id) AS projs
    WHERE projs.project_id = p_id;

    -- Return happiness or otherwise
    IF matching_project_count > 0 THEN
        RETURN TRUE;
    END IF;    

    -- Default is no match
    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Check if bander is authorised to upload to project
DROP FUNCTION IF EXISTS ro_is_authorised_for_upload;

CREATE FUNCTION ro_is_authorised_for_upload(b_id uuid, p_id uuid) RETURNS boolean AS $$
DECLARE
  valid_bander BOOLEAN := FALSE;
  valid_project BOOLEAN := FALSE;
  valid_proj_membership BOOLEAN := FALSE;
BEGIN
    -- Ensure Bander is valid and active
    SELECT ro_is_active_bander(b_id) INTO valid_bander;
    IF valid_bander = FALSE THEN
        RETURN FALSE;
    END IF;

    -- Ensure Project is valid
    SELECT ro_is_project(p_id) INTO valid_project;
    IF valid_project = FALSE THEN
        RETURN FALSE;
    END IF;

    -- Ensure bander is a member of the project
    SELECT ro_bander_is_in_project(b_id, p_id) INTO valid_proj_membership;
    IF valid_proj_membership = FALSE THEN
        RETURN FALSE;
    END IF;

    -- TODO - Checks on Bander's Level within the project

    -- Passed all the checks! Must be authorized!
    RETURN TRUE;
END; $$
LANGUAGE PLPGSQL;


-- Check if bander is authorised to upload to project
DROP FUNCTION IF EXISTS ro_is_authorised_for_update;

CREATE FUNCTION ro_is_authorised_for_update(e_id uuid, b_id uuid, p_id uuid) RETURNS boolean AS $$
DECLARE
  valid_bander BOOLEAN := FALSE;
  valid_project BOOLEAN := FALSE;
  valid_proj_membership BOOLEAN := FALSE;
  valid_event_contributor BOOLEAN := FALSE;
BEGIN
    -- Ensure Bander is valid and active
    SELECT ro_is_active_bander(b_id) INTO valid_bander;
    IF valid_bander = FALSE THEN
        RETURN FALSE;
    END IF;

    -- Ensure Project is valid
    SELECT ro_is_project(p_id) INTO valid_project;
    IF valid_project = FALSE THEN
        RETURN FALSE;
    END IF;

    -- Ensure bander is a member of the project
    SELECT ro_bander_is_in_project(b_id, p_id) INTO valid_proj_membership;
    SELECT ro_is_event_contributor(e_id, b_id) INTO valid_event_contributor;

    IF valid_proj_membership = FALSE AND valid_event_contributor = FALSE THEN
      RETURN FALSE;
    END IF;

    -- TODO - Checks on Bander's Level within the project

    -- Passed all the checks! Must be authorized!
    RETURN TRUE;
END; $$
LANGUAGE PLPGSQL;


-- Check if bander is authorised to delete an event
DROP FUNCTION IF EXISTS ro_is_authorised_for_deletion;

CREATE FUNCTION ro_is_authorised_for_deletion(b_id uuid, e_id uuid) RETURNS boolean AS $$
DECLARE
  matching_event_count NUMERIC := 0;
BEGIN
    SELECT COUNT(event.id) INTO matching_event_count
    FROM event
    WHERE event.id = e_id AND (event.event_reporter_id = b_id OR event.event_provider_id = b_id OR event.event_owner_id = b_id);

    IF matching_event_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if the Bander is present
DROP FUNCTION IF EXISTS ro_is_bander;

CREATE FUNCTION ro_is_bander(b_id uuid) RETURNS boolean AS $$
DECLARE
  matching_bander_count NUMERIC := 0;
BEGIN
    SELECT COUNT(bander.id) INTO matching_bander_count
    FROM bander
    WHERE bander.id = b_id;

    IF matching_bander_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Check if the bander number is unique
DROP FUNCTION IF EXISTS ro_is_unique_nznbbs_certification_number(bander_id uuid, cert_number text);

CREATE FUNCTION ro_is_unique_nznbbs_certification_number(bander_id uuid, cert_number text) RETURNS boolean AS $$
DECLARE
  matching_bander_count NUMERIC := 0;
BEGIN
    SELECT count(bander.nznbbs_certification_number) INTO matching_bander_count 
    FROM bander 
    WHERE (bander_id IS NULL OR bander.id != bander_id) AND bander.nznbbs_certification_number = cert_number;

    IF matching_bander_count > 0 THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END; $$
LANGUAGE PLPGSQL;

-- Add a person to the bander table
DROP FUNCTION IF EXISTS rw_add_bander;

CREATE FUNCTION rw_add_bander(b_id uuid, username text, person_name text, is_hidden boolean, bander_state enum_bander_state, primary_organisation text) RETURNS NUMERIC AS $$
DECLARE 
  v_count NUMERIC := 0;
BEGIN
  INSERT INTO bander (id, username, person_name, is_hidden, bander_state, primary_organisation) VALUES (b_id, username, person_name, is_hidden, bander_state, primary_organisation);
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN v_count;
END;  $$
LANGUAGE PLPGSQL;

-- Change a banders state to ACTIVE
DROP FUNCTION IF EXISTS rw_activate_bander;

CREATE FUNCTION rw_activate_bander(b_id uuid) RETURNS NUMERIC AS $$
DECLARE 
  update_count NUMERIC := 0;
BEGIN
  UPDATE bander SET bander_state = 'ACTIVE'
  WHERE id = b_id;
  GET DIAGNOSTICS update_count = ROW_COUNT;

  RETURN update_count;
END;  $$
LANGUAGE PLPGSQL;

-- Update a banders last login
DROP FUNCTION IF EXISTS rw_update_last_login;

CREATE FUNCTION rw_update_last_login(b_id uuid) RETURNS NUMERIC AS $$
DECLARE 
  update_count NUMERIC := 0;
BEGIN
  UPDATE bander SET last_login = CURRENT_TIMESTAMP(0)
  WHERE id = b_id;
  GET DIAGNOSTICS update_count = ROW_COUNT;

  RETURN update_count;
END;  $$
LANGUAGE PLPGSQL;


-- Convert NZTM to WGS84
-- Test Coordinates:
-- N 5441393m, E 1753950m
DROP FUNCTION IF EXISTS ro_nztm_to_wgs84;

CREATE FUNCTION ro_nztm_to_wgs84(easting numeric, northing numeric, OUT latitude numeric, OUT longitude numeric) AS $$
BEGIN
  latitude := ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(easting, northing), 2193), 4326));
  longitude := ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(easting, northing), 2193), 4326));
END;  $$
LANGUAGE PLPGSQL;

-- Convert NZMG to WGS84
-- Test Coordinates:
-- N 6003034m, E 2664116m
DROP FUNCTION IF EXISTS ro_nzmg_to_wgs84;

CREATE FUNCTION ro_nzmg_to_wgs84(easting numeric, northing numeric, OUT latitude numeric, OUT longitude numeric) AS $$
BEGIN
  latitude := ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(easting, northing), 27200), 4326));
  longitude := ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(easting, northing), 27200), 4326));
END;  $$
LANGUAGE PLPGSQL;

-- Get a specific banders marks
-- Added complexity which requires a POSTGRES function
-- We only want the latest event <-> mark_allocation association
--  to be used in the join
-- Naming convention applied for resource <-> resource joins
DROP FUNCTION IF EXISTS ro_bander_mark(b_id uuid, pagination_limit integer, pagination_token integer);

CREATE FUNCTION ro_bander_mark(b_id uuid, pagination_limit integer, pagination_token integer)
RETURNS TABLE (
  id uuid,
  row_creation_timestamp_ timestamp with time zone,
  row_creation_user_ text,
  row_update_timestamp_ timestamp with time zone,
  row_update_user_ text,
  row_creation_idx integer,
  prefix_number text,
  short_number text
) AS $$
BEGIN
    RETURN QUERY 
    SELECT m.*
    FROM mark_allocation AS ma
      INNER JOIN mark AS m ON m.id = ma.mark_id
      INNER JOIN event AS e ON ma.event_id = e.id
      LEFT JOIN (
      SELECT * FROM mark_allocation
        INNER JOIN event AS e2 ON mark_allocation.event_id = e2.id
      ) AS ma2
        ON (ma.mark_id = ma2.mark_id AND e.event_timestamp < ma2.event_timestamp)
    WHERE ma2.mark_id IS NULL AND ma.bander_id = b_id AND (m.row_creation_idx < pagination_token OR pagination_token IS NULL)
    LIMIT pagination_limit;
END
$$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS rw_export_query(query text, bucket_name text, object_path text);

CREATE FUNCTION rw_export_query(query text, bucket_name text, object_path text) RETURNS VOID AS $$
BEGIN
  PERFORM * from aws_s3.query_export_to_s3(query, 
   aws_commons.create_s3_uri(
	   bucket_name, 
	   object_path, 
	   'ap-southeast-2'),
   		options :='format csv, header, delimiter '','', force_quote *'
  );
END; $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS rw_import_query(table_name text, column_names text, bucket_name text, object_path text);

CREATE FUNCTION rw_import_query(table_name text, column_names text, bucket_name text, object_path text) RETURNS VOID AS $$
BEGIN
  PERFORM * from aws_s3.table_import_from_s3(table_name, 
  column_names,
  '(format csv, header)',
   aws_commons.create_s3_uri(
	   bucket_name, 
	   object_path, 
	   'ap-southeast-2')
  );
END; $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS ro_search_events_count(query text);

CREATE FUNCTION ro_search_events_count(query text)
RETURNS SETOF integer AS $$
DECLARE
  count_integer integer := NULL;
BEGIN
	RETURN QUERY EXECUTE query;
END
$$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_mark_history(_prefix_number text, _short_number text);

CREATE FUNCTION ro_mark_history(_prefix_number text, _short_number text)
RETURNS TABLE (
  prefix_number text,
  short_number text,
  event_timestamp timestamp with time zone,
  state text,
  person_name text
) AS $$
BEGIN
    RETURN QUERY 
    SELECT 
      m.prefix_number, m.short_number,
      e.event_timestamp,
      ms.state::text,
      b.person_name
    FROM mark AS m
    INNER JOIN mark_state AS ms ON ms.mark_id = m.id
    INNER JOIN event AS e ON e.id = ms.event_id
    INNER JOIN mark_allocation AS ma ON ma.event_id = e.id 
    INNER JOIN bander AS b ON b.id = ma.bander_id
    WHERE m.prefix_number = _prefix_number AND m.short_number = _short_number
    ORDER BY e.event_timestamp DESC;
END
$$
LANGUAGE PLPGSQL;

--check if mark short_numbers in combination with a given prefix are unique
DROP FUNCTION IF EXISTS ro_are_marks_unique(prefix text, range_array text[]);

CREATE FUNCTION ro_are_marks_unique(prefix text, range_array text[])
  RETURNS TABLE (
    prefix_number text,
    short_number text
  ) AS $$
BEGIN
  RETURN QUERY
  SELECT m.prefix_number, m.short_number
  FROM mark m
  WHERE m.prefix_number = prefix AND m.short_number = ANY (range_array);
END $$
LANGUAGE PLPGSQL;

-- check if marks are currently 'NEW' in terms of mark_status
DROP FUNCTION IF EXISTS ro_are_marks_new(marks_array text[]);

CREATE FUNCTION ro_are_marks_new(marks_array text[])
    RETURNS TABLE(
      mark_id uuid, 
      mark_state enum_mark_state
    ) AS $$ 
DECLARE 
  mark_array uuid[]:= marks_array::uuid[];
BEGIN
  RETURN QUERY
  SELECT distinct ms.mark_id, ms.state
  FROM mark_state ms
  WHERE ms.mark_id = ANY(mark_array) AND ms.state <> 'NEW';
END $$
LANGUAGE PLPGSQL;

--get last short_number for a given prefix
--note: you might want to change the funciton name or tweak it in general, this function started
--out trying to return a boolean and valid last short_number
DROP FUNCTION IF EXISTS ro_get_last_short_number(prefix_number_ text);

CREATE FUNCTION ro_get_last_short_number(prefix_number_ text)
RETURNS integer

AS $$
DECLARE
  last_short_number bigint;
BEGIN
  SELECT 
  MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint) INTO last_short_number
  FROM mark
  WHERE prefix_number = prefix_number_;

  RETURN last_short_number;
END $$
LANGUAGE PLPGSQL;

-- This function checks whether a prefix number exists within the marks table
DROP FUNCTION IF EXISTS ro_is_supported_prefix(prefix_number_ text);

CREATE FUNCTION ro_is_supported_prefix(prefix_number_ text)
RETURNS boolean

AS $$
DECLARE
  prefix_number_count numeric := 0;
BEGIN
SELECT COUNT(mark.prefix_number) INTO prefix_number_count
  FROM mark
  WHERE mark.prefix_number = prefix_number_
  LIMIT 1;
  
  IF prefix_number_count > 0 THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END $$
LANGUAGE PLPGSQL;


-- FUNCTION USED TO UPDATE ALLOCATION_IDX, STATE_IDX AND RESPECTIVE IS_CURRENT VALUES
-- Takes an array of mark_ids to update as input
DROP FUNCTION IF EXISTS rw_update_latest_mark_allocation_and_state(mark_id_array text[]);

CREATE FUNCTION rw_update_latest_mark_allocation_and_state(mark_id_array text[])
RETURNS NUMERIC AS $$
DECLARE
   v_count NUMERIC := 0;
BEGIN

  -- Added allocation reset to repair bugs encountered on 30/03/2021
  UPDATE mark_allocation SET
	is_current = FALSE
	WHERE mark_id IN (select(unnest(mark_id_array::uuid[])));

  UPDATE mark_allocation SET
	allocation_idx = tempo.update_idx
	FROM    
		(SELECT 
		 	m.prefix_number, m.short_number, 
		 	ma.id AS join_id, ma.mark_id, 
			e.event_timestamp, 
		 	row_number() OVER (PARTITION BY ma.mark_id ORDER BY e.event_timestamp ASC) AS update_idx
	FROM mark as m
	INNER JOIN mark_allocation as ma ON ma.mark_id = m.id
	INNER JOIN event as e ON e.id = ma.event_id
	WHERE ma.mark_id IN (select(unnest(mark_id_array::uuid[])))) AS tempo
	WHERE id = tempo.join_id;
	
	WITH update_ids AS 
	(
	  SELECT mark_id, MAX(allocation_idx) AS allocation_idx
	  FROM mark_allocation as ma1
	  WHERE ma1.mark_id IN (select(unnest(mark_id_array::uuid[])))
	  GROUP BY mark_id
	)
	UPDATE mark_allocation SET
	is_current = TRUE
	FROM update_ids
	WHERE mark_allocation.mark_id = update_ids.mark_id AND mark_allocation.allocation_idx = update_ids.allocation_idx;

  -- Added state reset to repair bugs encountered on 30/03/2021
  UPDATE mark_state SET
	is_current = FALSE
	WHERE mark_id IN (select(unnest(mark_id_array::uuid[])));

	UPDATE mark_state SET
	state_idx = tempo.update_idx
	FROM    
		(SELECT 
		 	m.prefix_number, m.short_number, 
		 	ms.id AS join_id, ms.mark_id, 
			e.event_timestamp, 
		 	row_number() OVER (PARTITION BY ms.mark_id ORDER BY e.event_timestamp ASC) AS update_idx
	FROM mark as m
	INNER JOIN mark_state as ms ON ms.mark_id = m.id
	INNER JOIN event as e ON e.id = ms.event_id
	WHERE mS.mark_id IN (select(unnest(mark_id_array::uuid[])))) AS tempo
	WHERE id = tempo.join_id;

	WITH update_ids AS 
	(
	  SELECT mark_id, MAX(state_idx) AS state_idx
	  FROM mark_state AS ms1
	  WHERE ms1.mark_id IN (select(unnest(mark_id_array::uuid[])))
	  GROUP BY mark_id
	)
	UPDATE mark_state SET
	is_current = TRUE
	FROM update_ids
	where update_ids.mark_id = mark_state.mark_id AND mark_state.state_idx = update_ids.state_idx;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN v_count;
END;  $$
LANGUAGE PLPGSQL;


-- FUNCTION USED TO UPDATE STATE_IDX AND IS_CURRENT VALUES FOR MARK_STATE ONLY
-- Takes an array of mark_ids to update as input
DROP FUNCTION IF EXISTS rw_update_latest_mark_state(mark_id_array text[]);

CREATE FUNCTION rw_update_latest_mark_state(mark_id_array text[])
RETURNS NUMERIC AS $$
DECLARE
   v_count NUMERIC := 0;
BEGIN
	UPDATE mark_state SET
	state_idx = tempo.update_idx
	FROM    
		(SELECT 
		 	m.prefix_number, m.short_number, 
		 	ms.id AS join_id, ms.mark_id, 
			e.event_timestamp, 
		 	row_number() OVER (PARTITION BY ms.mark_id ORDER BY e.event_timestamp ASC) AS update_idx
	FROM mark as m
	INNER JOIN mark_state as ms ON ms.mark_id = m.id
	INNER JOIN event as e ON e.id = ms.event_id
	WHERE mS.mark_id IN (select(unnest(mark_id_array::uuid[])))) AS tempo
	WHERE id = tempo.join_id;

	WITH update_ids AS 
	(
	  SELECT mark_id, MAX(state_idx) AS state_idx
	  FROM mark_state AS ms1
	  WHERE ms1.mark_id IN (select(unnest(mark_id_array::uuid[])))
	  GROUP BY mark_id
	)
	UPDATE mark_state SET
	is_current = TRUE
	FROM update_ids
	where update_ids.mark_id = mark_state.mark_id AND mark_state.state_idx = update_ids.state_idx;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN v_count;
END;  $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS ro_get_project_coordinator(p_id text);

CREATE FUNCTION ro_get_project_coordinator(p_id text)
RETURNS uuid
  AS $$
DECLARE
 project_coordinator_id uuid;
BEGIN
    SELECT p.coordinator_id INTO project_coordinator_id
    FROM project as p
    WHERE p.id = p_id::uuid;
	
	RETURN project_coordinator_id;
END;   $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS ro_get_distinct_prefix_numbers();

CREATE FUNCTION ro_get_distinct_prefix_numbers()
RETURNS text[]
  AS $$
DECLARE
 distinct_prefix_numbers text[];
BEGIN
    SELECT ARRAY(SELECT distinct prefix_number from mark) INTO distinct_prefix_numbers;
	
	RETURN distinct_prefix_numbers;
END;   $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS ro_bird_event_count(b_id text);

CREATE FUNCTION ro_bird_event_count(b_id text)
RETURNS integer

AS $$
DECLARE
  event_count INTEGER;
BEGIN
  SELECT 
  COUNT(e.id) INTO event_count
  FROM event AS e
  WHERE e.bird_id = b_id::uuid;

  RETURN event_count;
END $$
LANGUAGE PLPGSQL;
-- Are Marks New
DROP FUNCTION IF EXISTS ro_is_mark_new(mark_ids text[]);

CREATE FUNCTION ro_is_mark_new(mark_ids text[])
RETURNS TABLE (
  mark_id uuid,
  mark_state enum_mark_state
) AS $$
Declare 
mark_array uuid[]:= mark_ids::uuid[];
BEGIN
RETURN QUERY
SELECT distinct ms.mark_id, ms.state
FROM mark_state ms
WHERE ms.mark_id = ANY(mark_array) AND ms.state <> 'NEW';
END $$
LANGUAGE PLPGSQL;

--Do Marks exist in DB ## TODO

DROP FUNCTION IF EXISTS ro_do_marks_exist(mark_ids text[]);

CREATE FUNCTION ro_do_marks_exist(mark_ids text[])
RETURNS TABLE (
mark_id uuid
) AS $$
DECLARE list_ids uuid[] := mark_ids::uuid[];
BEGIN

END $$
LANGUAGE PLPGSQL;

--## is contetnId 
DROP FUNCTION IF EXISTS ro_is_content;
CREATE FUNCTION ro_is_content(c_id integer) RETURNS boolean AS $$
DECLARE
  matching_content_count NUMERIC := 0;
BEGIN
    SELECT count(cms_content.id) INTO matching_content_count 
    FROM cms_content 
    WHERE cms_content.id = c_id;
    IF matching_content_count > 0 THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if the Mark is present
DROP FUNCTION IF EXISTS ro_is_mark;

CREATE FUNCTION ro_is_mark(m_id uuid) RETURNS boolean AS $$
DECLARE
  matching_mark_count NUMERIC := 0;
BEGIN
    SELECT count(mark.id) INTO matching_mark_count 
    FROM mark 
    WHERE mark.id = m_id;

    IF matching_mark_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if a given bander is a given mark's current allocatee
DROP FUNCTION IF EXISTS ro_is_mark_allocatee;

CREATE FUNCTION ro_is_mark_allocatee(m_id uuid, b_id uuid) RETURNS boolean AS $$
DECLARE
  matching_mark_allocation_count NUMERIC := 0;
BEGIN
    SELECT count(mark_allocation.mark_id) INTO matching_mark_allocation_count
    FROM mark_allocation 
    WHERE mark_allocation.mark_id = m_id AND mark_allocation.bander_id = b_id AND is_current = TRUE;

    IF matching_mark_allocation_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Get a mark's current mark_state
DROP FUNCTION IF EXISTS ro_latest_mark_state;

CREATE FUNCTION ro_latest_mark_state(m_id uuid)
RETURNS text
  AS $$
DECLARE
 current_state text;
BEGIN
    SELECT mark_state.state INTO current_state
    FROM mark_state 
    WHERE mark_state.mark_id = m_id AND is_current = TRUE;
	
	RETURN current_state;
END;   $$
LANGUAGE PLPGSQL;


-- Check if an event id represents a real event
DROP FUNCTION IF EXISTS ro_is_event;

CREATE FUNCTION ro_is_event(e_id uuid) RETURNS boolean AS $$
DECLARE
  matching_event_count NUMERIC := 0;
BEGIN
    SELECT count(event.id) INTO matching_event_count 
    FROM event 
    WHERE event.id = e_id;

    IF matching_event_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Check if a list of event ids all represent a real event
DROP FUNCTION IF EXISTS ro_are_events;

CREATE FUNCTION ro_are_events(e_ids text[]) RETURNS boolean AS $$
DECLARE
  matching_event_count NUMERIC := 0;
BEGIN
    SELECT count(event.id) INTO matching_event_count 
    FROM event 
    WHERE event.id = ANY(e_ids::uuid[]);

    IF matching_event_count = array_length(e_ids, 1) THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if a given event is associated witha given user's projects
DROP FUNCTION IF EXISTS ro_is_event_from_user_project;

CREATE FUNCTION ro_is_event_from_user_project(e_id uuid, b_id uuid) RETURNS boolean AS $$
DECLARE
  matching_event_project_membership_count NUMERIC := 0;
  matching_event_project_coordinator_count NUMERIC := 0;
BEGIN
    SELECT COUNT(e.id) INTO matching_event_project_membership_count 
      FROM event AS e
      INNER JOIN project AS p ON p.id = e.project_id
      INNER JOIN project_bander_membership AS pbm ON pbm.project_id = p.id
      WHERE pbm.bander_id = b_id AND pbm.is_deleted = false AND e.id = e_id;

    SELECT COUNT(e.id) INTO matching_event_project_coordinator_count 
      FROM event AS e
      INNER JOIN project AS p ON p.id = e.project_id
      WHERE p.coordinator_id = b_id AND e.id = e_id;

    IF matching_event_project_membership_count > 0
    OR matching_event_project_coordinator_count > 0
    THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if a given bander is a contributor to a given event
DROP FUNCTION IF EXISTS ro_is_event_contributor;

CREATE FUNCTION ro_is_event_contributor(e_id uuid, b_id uuid) RETURNS boolean AS $$
DECLARE
  matching_event_contributor_count NUMERIC := 0;
BEGIN
    SELECT COUNT(e.id) INTO matching_event_contributor_count 
      FROM event AS e
      WHERE (e.event_reporter_id = b_id OR e.event_provider_id = b_id OR e.event_owner_id = b_id) 
          AND e.id = e_id;

    IF matching_event_contributor_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if a given event's project associated has a null or lapsed moratorium timestamp 
-- (i.e. available to the full banding community)
DROP FUNCTION IF EXISTS ro_is_event_project_public;

CREATE FUNCTION ro_is_event_project_public(e_id uuid) RETURNS boolean AS $$
DECLARE
  matching_event_count NUMERIC := 0;
BEGIN
    SELECT COUNT(e.id) INTO matching_event_count 
      FROM event AS e
      INNER JOIN project AS p ON p.id = e.project_id
      WHERE 
          (default_moratorium_expiry IS NULL OR default_moratorium_expiry < NOW())
          AND e.id = e_id;

    IF matching_event_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if a given event's project associated has a null or lapsed moratorium timestamp 
-- (i.e. available to the full banding community)
DROP FUNCTION IF EXISTS ro_is_bird_contributor;

CREATE FUNCTION ro_is_bird_contributor(e_id uuid, b_id uuid) RETURNS boolean AS $$
DECLARE
  matching_bird_event_count NUMERIC := 0;
BEGIN
    SELECT COUNT(e.id) into matching_bird_event_count
      FROM event AS e
      INNER JOIN bander AS bo ON bo.id = e.event_owner_id
      INNER JOIN bander AS bp ON bp.id = e.event_provider_id
      INNER JOIN bander AS br ON br.id = e.event_reporter_id
        INNER JOIN (
          -- subquery here:
          SELECT event.bird_id
          FROM event
          WHERE event.id = e_id
        ) AS bird_id_lookup ON e.bird_id = bird_id_lookup.bird_id 
      WHERE (bo.id = b_id OR bp.id = b_id OR br.id = b_id);

    IF matching_bird_event_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Returns a boolean indicating whether a bander is part of a project
DROP FUNCTION IF EXISTS ro_bander_is_project_manager;

CREATE FUNCTION ro_bander_is_project_manager(b_id uuid, p_id uuid) RETURNS BOOLEAN AS $$
DECLARE
  matching_project_count NUMERIC := 0;  
BEGIN
    -- Check if the passed project is present
    SELECT COUNT(id) INTO matching_project_count
    FROM project
    WHERE id = p_id AND coordinator_id = b_id;

    -- Return happiness or otherwise
    IF matching_project_count > 0 THEN
        RETURN TRUE;
    END IF;    

    -- Default is no match
    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- cms-attachments is object path
DROP FUNCTION IF EXISTS ro_is_object_path;
 
CREATE FUNCTION ro_is_object_path(o_path text) RETURNS BOOLEAN AS $$
DECLARE
  matching_attachment_count NUMERIC := 0;
BEGIN
    SELECT count(cms_attachment.object_path) INTO matching_attachment_count 
    FROM cms_attachment
    WHERE cms_attachment.object_path= o_path;
    IF matching_attachment_count > 0 THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Returns a boolean indicating whether a bander can access an event transfer
DROP FUNCTION IF EXISTS ro_bander_can_access_event_transfer;

CREATE FUNCTION ro_bander_can_access_event_transfer(e_id uuid, b_id uuid) RETURNS BOOLEAN AS $$
DECLARE
  matching_event_count NUMERIC := 0;
BEGIN
    SELECT count(id) INTO matching_event_count 
    FROM vw_transfer_summary
    WHERE id = e_id AND (transfer_provider_id = b_id OR transfer_recipient_id = b_id);
    IF matching_event_count > 0 THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;
 
-- cms-attachments is attachmentId
DROP FUNCTION IF EXISTS ro_is_attachment;
CREATE FUNCTION ro_is_attachment(a_id integer) RETURNS BOOLEAN AS $$
DECLARE
  matching_attachment_count NUMERIC := 0;
BEGIN
    SELECT count(cms_attachment.id) INTO matching_attachment_count 
    FROM cms_attachment
    WHERE cms_attachment.id = a_id;
    IF matching_attachment_count > 0 THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- check matview not currently active
-- pg_stat_activity returns the call itself which contains the matview name so need to check count is > 1
DROP FUNCTION IF EXISTS ro_is_matview_refreshing;
CREATE FUNCTION ro_is_matview_refreshing(matview_name text) RETURNS BOOLEAN AS $$
DECLARE
  matching_active_processes NUMERIC := 0;
BEGIN
    SELECT COUNT(*) INTO matching_active_processes
    FROM pg_stat_activity
    WHERE state = 'active'
			AND query NOT LIKE '%pg_stat%'
			AND query like '%' || matview_name || '%';
		IF matching_active_processes > 1 THEN
			RETURN TRUE;
		END IF;
		RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_bird_travel_timeline;
CREATE FUNCTION ro_bird_travel_timeline(b_id uuid)
RETURNS TABLE (
  id uuid,
  event_timestamp timestamp with time zone,
  distance double precision
 ) AS $$
BEGIN
  RETURN QUERY 
    SELECT
      event.id,
      event.event_timestamp,
      ST_Distance(location, lag(location, 1) OVER (ORDER by event.event_timestamp ASC))
    FROM event
    where event.bird_id = b_id;
END; $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS ro_bird_location_delta_first_to_last;
CREATE FUNCTION ro_bird_location_delta_first_to_last(b_id uuid)
RETURNS DOUBLE PRECISION AS $$
DECLARE
  location_delta DOUBLE PRECISION := 0;
  BEGIN
    WITH first_event_with_loc AS (
      SELECT * 
      FROM event
      WHERE bird_id = b_id
      AND latitude is not NULL
      AND longitude is not NULL
      ORDER BY event_timestamp ASC
      LIMIT 1
    ),
    last_event_with_loc AS (
      SELECT * 
      FROM event
      WHERE bird_id = b_id
      AND latitude is not NULL
      AND longitude is not NULL
      ORDER BY event_timestamp DESC
      LIMIT 1
    )
    SELECT distance INTO location_delta
    FROM first_event_with_loc AS fe
    INNER JOIN last_event_with_loc AS le ON le.bird_id = fe.bird_id AND le.id != fe.id
    CROSS JOIN LATERAL ST_Distance(fe.location, le.location) distance;
	RETURN location_delta;
END; $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_bird_location_delta_most_recent;
CREATE FUNCTION ro_bird_location_delta_most_recent(b_id uuid)
RETURNS DOUBLE PRECISION AS $$
DECLARE
  location_delta DOUBLE PRECISION := 0;
  BEGIN
    WITH last_two_events_loc as
    ( 
      SELECT
        e.id,
        e.event_timestamp,
        e.bird_id,
        e.location,
        dense_rank() over (PARTITION BY bird_id order by event_timestamp desc, row_creation_timestamp_ desc) row_number      FROM event AS e 
      WHERE bird_id = b_id
      LIMIT 2
    )
    SELECT
      distance INTO location_delta
    FROM last_two_events_loc AS le
      INNER JOIN last_two_events_loc sle ON sle.bird_id = le.bird_id 
      AND sle.id != le.id
      CROSS JOIN LATERAL ST_Distance(sle.location, le.location) distance
    WHERE le.row_number > sle.row_number;
	RETURN location_delta;
END; $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_bird_status_summary;
CREATE FUNCTION ro_bird_status_summary(b_id uuid)
RETURNS TABLE (
  id uuid,
  event_timestamp timestamp with time zone,
  out_status_code text
 ) AS $$
DECLARE
BEGIN
  RETURN QUERY 
    SELECT
      e.id,
      e.event_timestamp,
      cm.value
    FROM event AS e
	INNER JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
    where e.bird_id = b_id
	ORDER BY e.event_timestamp;
END; $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS rw_remove_deleted_links_from_content;

CREATE FUNCTION rw_remove_deleted_links_from_content(href text) RETURNS NUMERIC AS $$
DECLARE 
  v_count NUMERIC := 0;
BEGIN
  UPDATE cms_content SET html = replace(html, href, '/not-found')
  WHERE html like '%' || href || '%';
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN v_count;
END;  $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_get_monthly_uploads;
--count number of uploads over the last 3 months for a given bander
CREATE FUNCTION ro_get_monthly_uploads(b_id uuid) 
RETURNS int AS $$ 

BEGIN
    RETURN (SELECT COUNT (*) FROM bander_uploads WHERE bander_id = b_id AND row_creation_timestamp_ >= date_trunc('month', now()) - interval '3 month');
END
$$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS ro_admin_get_monthly_uploads;
--count number of uploads over the last 3 months for all users (i.e. available to admin)
CREATE FUNCTION ro_admin_get_monthly_uploads() 
RETURNS int AS $$ 

BEGIN
    RETURN (SELECT COUNT (*) FROM bander_uploads WHERE row_creation_timestamp_ >= date_trunc('month', now()) - interval '3 month');
END
$$
LANGUAGE PLPGSQL;

-- Check if an spreadsheet id represents a real event
DROP FUNCTION IF EXISTS ro_is_bander_upload;

CREATE FUNCTION ro_is_bander_upload(u_id uuid) RETURNS boolean AS $$
DECLARE
  matching_upload_count NUMERIC := 0;
BEGIN
    SELECT count(bander_uploads.id) INTO matching_upload_count 
    FROM bander_uploads 
    WHERE bander_uploads.id = u_id;

    IF matching_upload_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


-- Check if bander is authorised to view bander upload
DROP FUNCTION IF EXISTS ro_can_view_upload;

CREATE FUNCTION ro_can_view_upload(u_id uuid, b_id uuid) RETURNS boolean AS $$
DECLARE
  p_id uuid := null;
  valid_bander BOOLEAN := FALSE;
  valid_project BOOLEAN := FALSE;
  valid_proj_membership BOOLEAN := FALSE;
  valid_owner_count NUMERIC := 0;
BEGIN
    -- Get spreadsheet upload project
    SELECT project_id INTO p_id
    FROM bander_uploads where id = u_id;

    -- Ensure Bander is valid and active
    SELECT ro_is_active_bander(b_id) INTO valid_bander;
    IF valid_bander = FALSE THEN
        RETURN FALSE;
    END IF;

    -- Ensure Project is valid
    SELECT ro_is_project(p_id) INTO valid_project;
    IF valid_project = FALSE THEN
        RETURN FALSE;
    END IF;

    -- Check if bander is a member of the project
    SELECT ro_bander_is_in_project(b_id, p_id) INTO valid_proj_membership;

    -- OR, ensure bander is owner of the upload
    SELECT count(bander_uploads.id) INTO valid_owner_count
    FROM bander_uploads 
    WHERE bander_uploads.id = u_id AND bander_uploads.bander_id = b_id;

    IF valid_proj_membership = FALSE AND valid_owner_count <= 0 THEN
      RETURN FALSE;
    END IF;

    -- Passed all the checks! Must be authorized!
    RETURN TRUE;
END; $$
LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS rw_export_environment;

CREATE FUNCTION rw_export_environment(env text) RETURNS text AS $$
DECLARE
	env_bucket text := 'example-birdbanding-spa-client-infra-userassetsbucket-xxxxx';
	s3_buckets json := '{"example": "example-birdbanding-spa-client-infra-userassetsbucket-xxxxx"'::json;
	s3_folder text := NULL;
	tables_for_export json := '["bander","bander_certifications","bander_downloads","bander_uploads",
								"bird","certification_media","characteristic","characteristic_measurement",
								"cms_attachment","cms_content","event","event_media","mark","mark_allocation",
								"mark_configuration","mark_state","project","project_bander_invitations",
								"project_bander_membership","project_notices","public_event","public_event_media",
								"spatial_ref_sys","species","species_group","species_group_membership"]'::json;
	_table text := NULL;
	_query text := NULL;
	s3_table_path text := NULL;
	-- Error handling
	v_state   text;
    v_msg     text;
    v_detail  text;
    v_hint    text;
    v_context text;
BEGIN
	-- Select the correct s3 bucket to export to
	SELECT s3_buckets->>env INTO env_bucket;
	RAISE NOTICE 'Exporting to bucket %', env_bucket;
	
	-- Select the relative path for all of the exports
	RAISE NOTICE 'Exporting to path %', 'csv_backups/' || replace(replace(replace(to_char(NOW() AT TIME ZONE 'NZ', 'YYYY-MM-DD HH24:MI:SS'), ' ', '_'), '-', '_'), ':', '_') || '/';
	SELECT 'csv_backups/' 
			|| replace(replace(replace(to_char(NOW() AT TIME ZONE 'NZ', 'YYYY-MM-DD HH24:MI:SS'), ' ', '_'), '-', '_'), ':', '_') 
			|| '/'
		INTO s3_folder;
	
	-- Loop through each table and export to S3
	FOR _table IN SELECT * FROM json_array_elements_text(tables_for_export)
	LOOP
		RAISE NOTICE 'Query: SELECT * FROM %', _table;
		RAISE NOTICE 'Exporting to: %', s3_folder || _table || '.csv';
		SELECT 'SELECT * FROM ' || _table || ';' INTO _query;
		SELECT s3_folder || _table || '.csv' INTO s3_table_path;
		-- SELECT rw_export_query('SELECT * FROM bander;', env_bucket, s3_table_path);
		PERFORM * from aws_s3.query_export_to_s3(
			_query, 
			aws_commons.create_s3_uri(
				env_bucket, 
				s3_table_path, 
				'ap-southeast-2'),
			options :='format csv, header, delimiter '','', force_quote *'
		);
		RAISE NOTICE 'Completed export to: %', s3_folder || _table || '.csv';
	END LOOP;
	
	RETURN 'SUCCESS';
EXCEPTION WHEN OTHERS THEN
	RAISE NOTICE 'FAILED TO EXPORT ENVIRONMENT';
	GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        raise notice E'Got exception:
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', v_state, v_msg, v_detail, v_hint, v_context;
	RETURN 'FAILURE';
END;
$$
LANGUAGE PLPGSQL;


-- Check if a bander has a stock entry for a given prefix
DROP FUNCTION IF EXISTS ro_bander_has_prefix_stock_row;

CREATE FUNCTION ro_bander_has_prefix_stock_row(_bander_id uuid, _prefix_number text) RETURNS boolean AS $$
DECLARE
  matching_row_count NUMERIC := 0;
BEGIN
    SELECT count(m.bander_id) INTO matching_row_count 
    FROM mark_stock_aggregation_rollup AS m
    WHERE m.prefix_number = _prefix_number 
      AND m.bander_id = _bander_id;

    IF matching_row_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS ro_bander_has_prefix_in_stock;

CREATE FUNCTION ro_bander_has_prefix_in_stock(_bander_id uuid, _prefix_number text) RETURNS boolean AS $$
DECLARE
  matching_mark_count NUMERIC := 0;
BEGIN
    SELECT count(m.id) INTO matching_mark_count 
    FROM mark AS m
    INNER JOIN mark_allocation AS ma ON ma.mark_id = m.id
    INNER JOIN mark_state AS ms ON ms.mark_id = m.id
    WHERE m.prefix_number = _prefix_number 
      AND ma.bander_id = _bander_id AND ma.is_current = TRUE
      AND ms.state IN ('NEW', 'ALLOCATED', 'RETURNED') and ms.is_current = TRUE;

    IF matching_mark_count > 0 THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END; $$
LANGUAGE PLPGSQL;

-- Custom Left padding implementation
DROP FUNCTION IF EXISTS lpad_upto;

CREATE FUNCTION lpad_upto(text, int, text) RETURNS TEXT AS $$
BEGIN
    IF LENGTH($1) >= $2 THEN
        RETURN $1;
    END IF;
    RETURN LPAD($1, $2, $3);
END;
$$ LANGUAGE PLPGSQL;

-- UPDATE THE STOCK LEVELS FOR BANDING OFFICE
DROP FUNCTION IF EXISTS rw_update_banding_office_stock;

CREATE FUNCTION rw_update_banding_office_stock(_b_ids text[], _prefix_numbers text[]) RETURNS NUMERIC AS $$
DECLARE 
  update_count NUMERIC := 0;
BEGIN
  -- Reset all marks for the selected prefixes
  UPDATE mark_stock_aggregation_rollup
  SET number_of_bands=0,
      last_short_number='-'
  WHERE prefix_number = ANY(_prefix_numbers)
    AND bander_id = ANY(_b_ids::uuid[]);

  -- Complete the update for all bands in stock
  UPDATE mark_stock_aggregation_rollup
  SET number_of_bands=subquery.count,
      last_short_number=subquery.max_short_number
  FROM (
    WITH max_short_numbers AS (
    SELECT prefix_number, lpad_upto(MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint)::text, 4, '0') AS max_short_number
    FROM mark
    WHERE prefix_number = ANY(_prefix_numbers)
    GROUP BY prefix_number
    )
    SELECT ma.bander_id, m.prefix_number, count(ma.mark_id), lsn.max_short_number
    FROM mark_allocation AS ma
    INNER JOIN mark_state as ms ON ma.mark_id = ms.mark_id
    INNER JOIN mark AS m ON m.id = ms.mark_id
    INNER JOIN max_short_numbers AS lsn ON lsn.prefix_number = m.prefix_number
    WHERE ma.bander_id = ANY(_b_ids::uuid[]) AND ma.is_current = TRUE
      AND ms.state IN ('NEW', 'ALLOCATED', 'RETURNED') AND ms.is_current = TRUE
      AND m.prefix_number = ANY(_prefix_numbers)
    GROUP BY ma.bander_id, m.prefix_number, lsn.max_short_number
  ) AS subquery
  WHERE subquery.bander_id = mark_stock_aggregation_rollup.bander_id
    AND subquery.prefix_number = mark_stock_aggregation_rollup.prefix_number;

  -- Ensure last short numbers are updated properly for all out of stock bands
  UPDATE mark_stock_aggregation_rollup
  SET number_of_bands=0,
      last_short_number=subquery.max_short_number
  FROM (
    SELECT prefix_number, lpad_upto(MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint)::text, 4, '0') AS max_short_number
    FROM mark
    WHERE prefix_number = ANY(_prefix_numbers)
    GROUP BY prefix_number
  ) AS subquery
  WHERE mark_stock_aggregation_rollup.bander_id = ANY(_b_ids::uuid[])
    AND subquery.prefix_number = mark_stock_aggregation_rollup.prefix_number
    AND mark_stock_aggregation_rollup.number_of_bands = 0;

  GET DIAGNOSTICS update_count = ROW_COUNT;

  RETURN update_count;
END;  $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS rw_update_bander_stock;

CREATE FUNCTION rw_update_bander_stock(_b_ids text[], _prefix_numbers text[]) RETURNS NUMERIC AS $$
DECLARE 
  update_count NUMERIC := 0;
BEGIN
  UPDATE mark_stock_aggregation_rollup
  SET number_of_bands=0,
      last_short_number='-'
  WHERE prefix_number = ANY(_prefix_numbers) 
    AND bander_id = ANY(_b_ids::uuid[]);

  UPDATE mark_stock_aggregation_rollup
  SET number_of_bands=subquery.count,
      last_short_number=subquery.max_short_number
  FROM (
    SELECT ma.bander_id, m.prefix_number, COUNT(ma.mark_id),lpad_upto(MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint)::text, 4, '0') AS max_short_number
    FROM mark_allocation AS ma
    INNER JOIN mark AS m ON m.id = ma.mark_id
	INNER JOIN mark_state AS ms ON ms.mark_id = ma.mark_id
    WHERE ma.is_current = TRUE AND ma.bander_id = ANY(_b_ids::uuid[])
	  AND ms.is_current = TRUE AND ms.state IN ('NEW', 'ALLOCATED', 'RETURNED')
      AND m.prefix_number = ANY(_prefix_numbers)
    GROUP BY ma.bander_id, m.prefix_number
  ) AS subquery
  WHERE subquery.bander_id = mark_stock_aggregation_rollup.bander_id
    AND subquery.prefix_number = mark_stock_aggregation_rollup.prefix_number;
  GET DIAGNOSTICS update_count = ROW_COUNT;

  RETURN update_count;
END;  $$
LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS rw_update_bander_stock_by_prefix;

CREATE FUNCTION rw_update_bander_stock_by_prefix(_banding_office_id text, _prefix_numbers text[]) RETURNS NUMERIC AS $$
DECLARE 
  update_count NUMERIC := 0;
BEGIN
  UPDATE mark_stock_aggregation_rollup
  SET number_of_bands=0,
      last_short_number='-'
  WHERE prefix_number = ANY(_prefix_numbers)
    AND bander_id != _banding_office_id::uuid;

  UPDATE mark_stock_aggregation_rollup
  SET number_of_bands=subquery.count,
      last_short_number=subquery.max_short_number
  FROM (
    SELECT ma.bander_id, m.prefix_number, COUNT(ma.mark_id),lpad_upto(MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint)::text, 4, '0') AS max_short_number
    FROM mark_allocation AS ma
    INNER JOIN mark AS m ON m.id = ma.mark_id
	  INNER JOIN mark_state AS ms ON ms.mark_id = ma.mark_id
    WHERE ma.is_current = TRUE AND ma.bander_id != _banding_office_id::uuid
	  AND ms.is_current = TRUE AND ms.state IN ('NEW', 'ALLOCATED', 'RETURNED')
      AND m.prefix_number = ANY(_prefix_numbers)
    GROUP BY ma.bander_id, m.prefix_number
  ) AS subquery
  WHERE subquery.bander_id = mark_stock_aggregation_rollup.bander_id
    AND subquery.prefix_number = mark_stock_aggregation_rollup.prefix_number;
  GET DIAGNOSTICS update_count = ROW_COUNT;

  RETURN update_count;
END;  $$
LANGUAGE PLPGSQL;


-- FUNCTION TO REFRESH ALL MARK_STATE/ALLOCATION TIMELINES BY AN EVENT ID 
-- -> NOTE: API TIMEOUT MEANS THIS MUST BE LESS THAN 10K DISTINCT MARKS TO AVOID AN ERROR IN THE TRANSACTION
-- Example IDs for performance testing: 
--   - da378bc2-656a-4f89-aade-9ec0a26b3b2f (~9k records)
--   - c0766f5e-3254-4f9f-b815-e6d634fb9557 (~8.4 records)
DROP FUNCTION IF EXISTS rw_update_latest_mark_allocation_and_state_by_event_id(_event_id text);

CREATE FUNCTION rw_update_latest_mark_allocation_and_state_by_event_id(_event_id text)
RETURNS NUMERIC AS $$

DECLARE
   v_count NUMERIC := 0;
BEGIN
  UPDATE mark_allocation SET
	is_current = FALSE
	WHERE mark_id IN (SELECT mark_id FROM mark_state AS ms2 WHERE ms2.event_id = _event_id::uuid);

  UPDATE mark_allocation SET
	allocation_idx = tempo.update_idx
	FROM    
		(SELECT 
		 	m.prefix_number, m.short_number, 
		 	ma.id AS join_id, ma.mark_id, 
			e.event_timestamp, 
		 	row_number() OVER (PARTITION BY ma.mark_id ORDER BY e.event_timestamp ASC) AS update_idx
	FROM mark as m
	INNER JOIN mark_allocation as ma ON ma.mark_id = m.id
	INNER JOIN event as e ON e.id = ma.event_id
	WHERE ma.mark_id IN (SELECT mark_id FROM mark_state AS ms2 WHERE ms2.event_id = _event_id::uuid)) AS tempo
	WHERE id = tempo.join_id;
	
	WITH update_ids AS 
	(
	  SELECT mark_id, MAX(allocation_idx) AS allocation_idx
	  FROM mark_allocation as ma1
	  WHERE ma1.mark_id IN (SELECT mark_id FROM mark_state AS ms2 WHERE ms2.event_id = _event_id::uuid)
	  GROUP BY mark_id
	)
	UPDATE mark_allocation SET
	is_current = TRUE
	FROM update_ids
	WHERE mark_allocation.mark_id = update_ids.mark_id AND mark_allocation.allocation_idx = update_ids.allocation_idx;

  UPDATE mark_state SET
	is_current = FALSE
	WHERE mark_id IN (SELECT mark_id FROM mark_state AS ms2 WHERE ms2.event_id = _event_id::uuid);

	UPDATE mark_state SET
	state_idx = tempo.update_idx
	FROM    
		(SELECT 
		 	m.prefix_number, m.short_number, 
		 	ms.id AS join_id, ms.mark_id, 
			e.event_timestamp, 
		 	row_number() OVER (PARTITION BY ms.mark_id ORDER BY e.event_timestamp ASC) AS update_idx
	FROM mark as m
	INNER JOIN mark_state as ms ON ms.mark_id = m.id
	INNER JOIN event as e ON e.id = ms.event_id
	WHERE mS.mark_id IN (SELECT mark_id FROM mark_state AS ms2 WHERE ms2.event_id = _event_id::uuid)) AS tempo
	WHERE id = tempo.join_id;

	WITH update_ids AS 
	(
	  SELECT mark_id, MAX(state_idx) AS state_idx
	  FROM mark_state AS ms1
	  WHERE ms1.mark_id IN (SELECT mark_id FROM mark_state AS ms2 WHERE ms2.event_id = _event_id::uuid)
	  GROUP BY mark_id
	)
	UPDATE mark_state SET
	is_current = TRUE
	FROM update_ids
	where update_ids.mark_id = mark_state.mark_id AND mark_state.state_idx = update_ids.state_idx;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN v_count;
END;  $$
LANGUAGE PLPGSQL;



GRANT USAGE ON SCHEMA public TO birdbanding_readonly;
GRANT USAGE ON SCHEMA aws_s3 TO birdbanding_readonly;
GRANT USAGE ON SCHEMA tiger TO birdbanding_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO birdbanding_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA tiger TO birdbanding_readonly;

GRANT USAGE ON SCHEMA public TO birdbanding_readwrite;
GRANT USAGE ON SCHEMA aws_s3 TO birdbanding_readwrite;
GRANT USAGE ON SCHEMA tiger TO birdbanding_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO birdbanding_readwrite;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA tiger TO birdbanding_readwrite;