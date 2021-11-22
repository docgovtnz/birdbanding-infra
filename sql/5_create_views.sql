/* Create views to simplify complex but not time-consuming queries */
/* ============================ */


-- ----------------------------------------------
/* Unfiltered Search Projects View */
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_mark_aggregation;
DROP VIEW IF EXISTS vw_project_list;

CREATE VIEW vw_project_list AS
    SELECT p.*, b.person_name AS project_manager_person_name, count(pbm.bander_id)::integer AS project_membership_count,
	        ec.project_event_count
    FROM project AS p
	LEFT JOIN bander AS b ON p.coordinator_id = b.id
  LEFT JOIN project_event_counts_matview AS ec ON ec.id = p.id
	LEFT JOIN project_bander_membership AS pbm ON p.id = pbm.project_id AND pbm.is_deleted = FALSE
	GROUP BY p.id, b.person_name,ec.project_event_count;

-- ----------------------------------------------
/* Unfiltered Bander Bird-ID relation */
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_bander_birds;

CREATE VIEW vw_bander_birds AS  
  WITH
  bander_birds
  AS
  (
    SELECT b.id AS bander_id, er.bird_id FROM bander as b
    INNER JOIN event AS er on er.event_reporter_id = b.id
    UNION
    SELECT b.id AS bander_id, ep.bird_id FROM bander as b
    INNER JOIN event AS ep on ep.event_provider_id = b.id
    UNION
    SELECT b.id AS bander_id, eo.bird_id FROM bander as b
    INNER JOIN event AS eo on eo.event_owner_id = b.id
  )
  SELECT distinct * 
  FROM bander_birds
  ORDER BY bird_id
;

-- ----------------------------------------------
/* Aggregated View of distinct bander transfer recipients */
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_distinct_transfer_recipients;

CREATE VIEW vw_distinct_transfer_recipients AS
  SELECT DISTINCT event_id, bander_id 
  FROM mark_allocation;



  -- ----------------------------------------------
/* Aggregated View of maximum bander certification levels */
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_transfer_summary;
DROP VIEW IF EXISTS vw_maximum_certification_level;
DROP AGGREGATE IF EXISTS custom_agg_max_cert_level(text);
DROP FUNCTION IF EXISTS cert_comparator(text, text);
DROP FUNCTION IF EXISTS finalise_max_cert_level;

CREATE FUNCTION cert_comparator (text, text)
returns text language sql
as $$
    select 
		case when $1 = 'L3' OR $2 = 'L3' then 'L3'
		 when $1 = 'L2' OR $2 = 'L2' then 'L2'
		 when $1 = 'L1' OR $2 = 'L1' then 'L1'
		 else 'UNCERTIFIED' end
$$;

CREATE FUNCTION finalise_max_cert_level (text)
returns text language sql
as $$
    select $1;
$$;

CREATE AGGREGATE custom_agg_max_cert_level (text) (
    sfunc = cert_comparator,
    finalfunc = finalise_max_cert_level,
    stype = text,
    initcond = 'UNCERTIFIED'
);

CREATE VIEW vw_maximum_certification_level AS
  SELECT b.id as bander_id, b.person_name, b.nznbbs_certification_number, custom_agg_max_cert_level(competency_level::text) as max_cert_level
  FROM bander AS b
  LEFT JOIN bander_certifications AS bc ON bc.bander_id = b.id 
  GROUP BY b.id, b.person_name;

  -- ----------------------------------------------
/* Aggregated View of Band Prefix Counts for Transfer Events */
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_transfer_prefix_number_counts;

CREATE VIEW vw_transfer_prefix_number_counts AS
  SELECT event_id, prefix_number, count(short_number)::integer,
  MIN(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint) AS min_short_number,
  MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint) AS max_short_number  
  FROM mark_allocation AS ma
  INNER JOIN mark AS m on ma.mark_id = m.id
  GROUP BY event_id, prefix_number;
  

  -- ----------------------------------------------
/* Aggregated View of Most Recent Mark Allocation */
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_mark_aggregation; /* Included for dependency*/
DROP VIEW IF EXISTS vw_admin_mark_aggregation; /* Included for dependency*/
DROP VIEW IF EXISTS vw_distinct_prefix_numbers;
DROP VIEW IF EXISTS vw_mark_latest;
DROP VIEW IF EXISTS vw_mark_latest_numeric_short_number;
DROP VIEW IF EXISTS vw_mark_last_short_number;
-- ----------------------------------------------
/* Aggregated Mark Last Short numbers */
-- ----------------------------------------------
-- Needed together given depedency

DROP VIEW IF EXISTS vw_mark_last_short_number;
CREATE VIEW vw_mark_last_short_number AS
  WITH msn AS 
  (
    SELECT prefix_number, MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint) AS max_short_number 
    FROM mark AS m
    GROUP BY prefix_number
  )
  SELECT msn.prefix_number, m.short_number AS max_short_number
  FROM msn
  INNER JOIN mark AS m ON msn.prefix_number = m.prefix_number AND msn.max_short_number = NULLIF(regexp_replace(m.short_number, '\D', '', 'g'), '')::bigint
;

-- ----------------------------------------------
/* Aggregated Mark Last Short numbers by bander */
-- ----------------------------------------------
-- Needed together given depedency

DROP VIEW IF EXISTS vw_bander_mark_last_short_number;
CREATE VIEW vw_bander_mark_last_short_number AS
WITH msn AS 
  (
    SELECT prefix_number, ma.bander_id, MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint) AS max_short_number 
    FROM mark AS m
	  INNER JOIN mark_state AS ms ON ms.mark_id = m.id AND ms.is_current = TRUE AND ms.state IN ('NEW', 'ALLOCATED', 'RETURNED')
    INNER JOIN mark_allocation AS ma ON ma.mark_id = ms.mark_id AND ma.event_id = ms.event_id
    GROUP BY prefix_number, bander_id
  )
  SELECT msn.prefix_number, m.short_number AS max_short_number, msn.bander_id
  FROM msn
  INNER JOIN mark AS m ON msn.prefix_number = m.prefix_number AND msn.max_short_number = NULLIF(regexp_replace(m.short_number, '\D', '', 'g'), '')::bigint
;

  -- ----------------------------------------------
/* View of latest mark details */
-- ----------------------------------------------
-- Dependency on mark_latest_matview
CREATE VIEW vw_mark_latest AS
  SELECT 
    m.id, m.prefix_number, m.short_number, m.short_number_numeric,
    m.bander_id,
    m.state,
    m.pagination_idx,
    ma.bander_id AS check_bander_id,
    b.nznbbs_certification_number,
    b.person_name,
    e.event_timestamp,
    ms.state AS check_mark_state,
    ms.event_id AS check_mark_state_event_id
  FROM mark_latest_matview AS m
  INNER JOIN mark_state AS ms ON ms.mark_id = m.id
  INNER JOIN mark_allocation AS ma ON ma.mark_id = m.id
  INNER JOIN bander AS b ON b.id = ma.bander_id
  INNER JOIN event AS e ON ms.event_id = e.id
  WHERE ms.is_current = true AND ma.is_current = true;

  -- ----------------------------------------------
/* View of latest mark details with numeric short number query support */
-- ----------------------------------------------
CREATE VIEW vw_mark_latest_numeric_short_number AS
  SELECT 
    m.id, m.prefix_number, m.short_number, m.short_number_numeric,
    ma.bander_id,
    ms.state,
    m.pagination_idx
  FROM mark_pagination_sort_band_number_matview AS m  
  INNER JOIN mark_allocation AS ma ON ma.mark_id = m.id
  INNER JOIN mark_state AS ms ON ms.mark_id = ma.mark_id
  WHERE ms.is_current = true AND ma.is_current = true;

  -- ----------------------------------------------
/* Bander-Projects and if they are fulfill the coordinator role*/
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_bander_projects_and_coordinators;

CREATE VIEW vw_bander_projects_and_coordinators AS
	WITH bander_projects_and_coordinators AS (
		(
			SELECT b.id, pbm.project_id, FALSE as is_coordinator
			FROM bander AS b
			INNER JOIN project_bander_membership AS pbm ON pbm.bander_id = b.id
      WHERE pbm.is_deleted = FALSE
		)
		UNION
		(
			SELECT b.id, p.id AS project_id, TRUE AS is_coordinator
			FROM bander AS b
			INNER JOIN project AS p ON p.coordinator_id = b.id
		)
	)
	SELECT bpac.id, bpac.project_id, bool_or(bpac.is_coordinator) AS is_coordinator, p.name
	FROM bander_projects_and_coordinators as bpac
	INNER JOIN project AS p ON p.id = bpac.project_id
  GROUP BY bpac.id, bpac.project_id, p.name;


  -- --------------------------------------------------------------------------
/* View of latest mark details (i.e. last short number for banders allocation) */
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_mark_aggregation;

CREATE VIEW vw_mark_aggregation AS
 SELECT ma.bander_id, m.prefix_number, 
  COUNT(ms.mark_id)::integer AS number_of_bands, 
  vlsn.max_short_number AS last_short_number
  FROM mark_state AS ms
  INNER JOIN mark_allocation as ma ON ma.mark_id = ms.mark_id AND ma.event_id = ms.event_id
  INNER JOIN mark AS m ON m.id = ms.mark_id
  INNER JOIN vw_bander_mark_last_short_number AS vlsn ON vlsn.prefix_number = m.prefix_number AND vlsn.bander_id = ma.bander_id
  WHERE ms.state IN ('NEW', 'ALLOCATED', 'RETURNED') AND ms.is_current = TRUE
  GROUP BY vlsn.max_short_number, m.prefix_number, ma.bander_id
  ORDER BY m.prefix_number;


    -- ----------------------------------------------------------------------------------------------------
/* View of latest mark details for admin (i.e. last short number for whole mark collection) */
-- ----------------------------------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_admin_mark_aggregation;

CREATE VIEW vw_admin_mark_aggregation AS
  SELECT vma.bander_id, m.prefix_number, 
  COUNT(vma.mark_id)::integer AS number_of_bands,
  vlsn.max_short_number AS last_short_number
  FROM mark_allocation AS vma
  INNER JOIN mark_state as ms ON ms.mark_id = vma.mark_id AND ms.event_id = vma.event_id
  INNER JOIN mark AS m ON m.id = vma.mark_id
  INNER JOIN vw_mark_last_short_number AS vlsn ON vlsn.prefix_number = m.prefix_number
  WHERE ms.state IN ('NEW', 'ALLOCATED', 'RETURNED') AND vma.is_current = TRUE
  GROUP BY vlsn.max_short_number, m.prefix_number, vma.bander_id
  ORDER BY m.prefix_number;

-- ----------------------------------------------
DROP VIEW IF EXISTS vw_distinct_transfer_recipients;

CREATE VIEW vw_distinct_transfer_recipients AS
  SELECT DISTINCT event_id, bander_id 
  FROM mark_allocation;
  
DROP VIEW IF EXISTS vw_transfer_summary;

CREATE VIEW vw_transfer_summary AS
 WITH transfer_aggregation AS (
 	SELECT e.id, e.event_type, e.event_timestamp, e.event_provider_id AS transfer_provider_id, 
	 e.transfer_recipient_id, e.mark_count AS mark_allocation_count
	 FROM event AS e
	 WHERE e.event_type = 'TRANSFER'
	 ORDER BY e.event_timestamp DESC
 )
 SELECT ta.*, 
 		pcl.person_name AS transfer_provider_person_name, 
		pcl.max_cert_level AS transfer_provider_max_cert_level, 
		rcl.person_name AS transfer_recipient_person_name, 
		rcl.max_cert_level AS transfer_recipient_max_cert_level
 FROM transfer_aggregation AS ta
 INNER JOIN vw_maximum_certification_level AS pcl ON pcl.bander_id = ta.transfer_provider_id
 INNER JOIN vw_maximum_certification_level AS rcl ON rcl.bander_id = ta.transfer_recipient_id
 ORDER BY ta.event_timestamp DESC;
 
 
DROP VIEW IF EXISTS vw_labelled_characteristic_measurments;

CREATE VIEW vw_labelled_characteristic_measurments AS
  SELECT c.name, c.display, cm.*
  FROM characteristic_measurement AS cm
  INNER JOIN characteristic AS c ON c.id = cm.characteristic_id;


DROP VIEW IF EXISTS vw_birds_to_marks;
CREATE VIEW vw_birds_to_marks AS
  SELECT distinct b.id, b.species_id, b.friendly_name, s.common_name_nznbbs , s.valid_band_prefixes, m.prefix_number, m.short_number
	FROM bird AS b
	INNER JOIN event AS e ON e.bird_id = b.id
	INNER JOIN mark_state AS ms ON ms.event_id = e.id
	INNER JOIN mark AS m ON m.id = ms.mark_id
	INNER JOIN species AS s ON s.id = b.species_id
	WHERE e.event_type IN (
		'FIRST_MARKING_IN_HAND', 'IN_HAND',
		'IN_HAND_PRE_CHANGE', 'IN_HAND_POST_CHANGE',
		'SIGHTING_BY_PERSON', 'RECORDED_BY_TECHNOLOGY'
		);


DROP VIEW IF EXISTS vw_bird_detail;
CREATE VIEW vw_bird_detail AS
  SELECT b.id, b.species_id, b.friendly_name, s.common_name_nznbbs , s.valid_band_prefixes
	FROM bird AS b
	INNER JOIN species AS s ON s.id = b.species_id;


DROP VIEW IF EXISTS vw_birds_to_first_marking_date;
CREATE VIEW vw_birds_to_first_marking_date AS
  SELECT b.id, e.id AS event_id, e.event_timestamp AS first_marking_timestamp
	FROM bird AS b
	INNER JOIN event AS e ON e.bird_id = b.id
	WHERE e.event_type = 'FIRST_MARKING_IN_HAND';

DROP VIEW IF EXISTS vw_birds_to_earliest_resighting;
CREATE VIEW vw_birds_to_earliest_resighting AS
  SELECT b.id, MIN(e.event_timestamp) AS earliest_resighting_timestamp
	FROM bird AS b
	INNER JOIN event AS e ON e.bird_id = b.id
	WHERE e.event_type != 'FIRST_MARKING_IN_HAND' AND e.event_bird_situation NOT IN ('CAPTIVE','SOURCE_SITE')
  GROUP BY (b.id);

DROP VIEW IF EXISTS vw_birds_earliest_death_resighting;
CREATE VIEW vw_birds_earliest_death_resighting AS
  SELECT b.id, MIN(e.event_timestamp) AS earliest_dead_timestamp
	FROM bird AS b
	INNER JOIN event AS e ON e.bird_id = b.id
	INNER JOIN characteristic_measurement AS cm ON cm.event_id = e.id
	WHERE cm.value LIKE '%DEAD%' AND cm.characteristic_id = 43
  GROUP BY (b.id);
  
DROP VIEW IF EXISTS vw_birds_latest_alive_resighting;
CREATE VIEW vw_birds_latest_alive_resighting AS
  SELECT b.id, MAX(e.event_timestamp) AS latest_alive_timestamp
	FROM bird AS b
	INNER JOIN event AS e ON e.bird_id = b.id
	INNER JOIN characteristic_measurement AS cm ON cm.event_id = e.id
	WHERE cm.value NOT LIKE '%DEAD%' AND cm.characteristic_id = 43
  GROUP BY (b.id);

DROP VIEW IF EXISTS vw_distinct_prefix_numbers;
CREATE VIEW vw_distinct_prefix_numbers AS
  WITH distinct_prefix_numbers AS (
    SELECT DISTINCT prefix_number
      FROM mark
  )
  SELECT 
    m.prefix_number,
    vlsn.max_short_number AS last_short_number
  FROM distinct_prefix_numbers AS m
  INNER JOIN vw_mark_last_short_number AS vlsn ON vlsn.prefix_number = m.prefix_number;


DROP VIEW IF EXISTS vw_events_simple;
CREATE VIEW vw_events_simple AS
   SELECT e.id, e.event_type, e.bird_id, e.row_creation_timestamp_, e.event_timestamp, e.event_reporter_id, e.event_provider_id, e.event_owner_id,
  		e.event_banding_scheme, e.event_bird_situation, e.latitude, e.longitude, e.location_description,
		p.id AS project_id, p.name AS project_name, p.default_moratorium_expiry,
		b.species_id, s.common_name_nznbbs, s.scientific_name_nznbbs, s.species_code_nznbbs,
  	sg.id AS species_group_id, sg.name AS species_group_name,
		br.nznbbs_certification_number AS reporter_nznbbs_certification_number,
		bp.nznbbs_certification_number AS provider_nznbbs_certification_number,
		bo.nznbbs_certification_number AS owner_nznbbs_certification_number,
		cm.id AS characteristic_measurement_id, cm.characteristic_id AS characteristic_id, cm.value AS characteristic_measurement_value
  FROM event AS e
  INNER JOIN project AS p ON p.id = e.project_id
  INNER JOIN bird AS b ON e.bird_id = b.id 
  INNER JOIN species AS s ON b.species_id = s.id
  INNER JOIN species_group_membership AS sgm ON sgm.species_id = s.id
  INNER JOIN species_group AS sg ON sgm.group_id = sg.id
  INNER JOIN bander AS br ON br.id = e.event_reporter_id
  INNER JOIN bander AS bp ON bp.id = e.event_provider_id
  INNER JOIN bander AS bo ON bo.id = e.event_owner_id
  LEFT JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
  WHERE e.event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER');
 
DROP VIEW IF EXISTS vw_bander_uploads;
CREATE VIEW vw_bander_uploads AS
   SELECT
    bu.id, b.id AS bander_id, b.person_name AS bander_name, 
    bu.row_creation_timestamp_ AS created_datetime,
    p.id AS project_id, p.name AS project_name,
    bu.no_of_rows, bu.storage_host, bu.object_path, bu.object_version,
    bu.file_size_in_bytes, bu.warnings_count, bu.criticals_count, bu.upload_status
    FROM bander_uploads AS bu
    INNER JOIN project AS p ON p.id = bu.project_id
    INNER JOIN bander AS b ON b.id = bu.bander_id;

DROP VIEW IF EXISTS vw_bander_upload_detail;
CREATE VIEW vw_bander_upload_detail AS
   SELECT
    bu.id, b.id AS bander_id, b.person_name AS bander_name, 
    bu.row_creation_timestamp_ AS created_datetime,
    p.id AS project_id, p.name AS project_name,
    bu.no_of_rows, bu.storage_host, bu.object_path, bu.object_version,
    bu.file_size_in_bytes, bu.errors, bu.warnings_count, bu.criticals_count, bu.upload_status
    FROM bander_uploads AS bu
    INNER JOIN project AS p ON p.id = bu.project_id
    INNER JOIN bander AS b ON b.id = bu.bander_id;

DROP VIEW IF EXISTS vw_bander_certifications;
CREATE VIEW vw_bander_certifications AS
   SELECT
    bc.*,
    sg.name
    FROM bander_certifications AS bc
    LEFT JOIN species_group AS sg ON bc.species_group_id = sg.id;


DROP VIEW IF EXISTS vw_distinct_mark_events;
CREATE VIEW vw_distinct_mark_events AS
    SELECT ma.event_id, ma.mark_id
    FROM mark_allocation AS ma
    UNION
    SELECT ms.event_id, ms.mark_id
    FROM mark_state AS ms;

DROP VIEW IF EXISTS vw_mark_event_summary;
CREATE VIEW vw_mark_event_summary AS
  SELECT ms.event_id, state, ma.bander_id, COUNT(ms.mark_id) AS mark_count, STRING_AGG(DISTINCT m.prefix_number::text, ',') AS distinct_prefix_numbers
  FROM mark_state AS ms
  INNER JOIN mark AS m ON m.id = ms.mark_id
  LEFT JOIN mark_allocation AS ma ON ma.event_id = ms.event_id AND ma.mark_id = ms.mark_id
  GROUP BY ms.event_id, ms.state, ma.bander_id;

DROP VIEW IF EXISTS vw_mark_history;
CREATE VIEW vw_mark_history AS
    SELECT e.id AS event_id, e.event_timestamp, 
	ma.mark_id AS ma_mark_id, ma.bander_id, b.person_name, 
	ms.mark_id AS ms_mark_id, ms.state
	FROM event AS e
	LEFT JOIN mark_allocation AS ma ON ma.event_id = e.id
	LEFT JOIN mark_state AS ms ON ms.event_id = e.id
	LEFT JOIN bander AS b ON b.id = ma.bander_id
	ORDER BY event_timestamp DESC;

DROP VIEW IF EXISTS vw_distinct_prefix_numbers_by_event;
CREATE VIEW vw_distinct_prefix_numbers_by_event AS
    SELECT STRING_AGG(DISTINCT prefix_number::text, ',') AS prefix_numbers, event_id
	FROM mark AS m
	INNER JOIN mark_state AS ms ON ms.mark_id = m.id
	GROUP BY ms.event_id;

DROP VIEW IF EXISTS vw_distinct_bird_banders;
CREATE VIEW vw_distinct_bird_banders AS
  SELECT 
    b.id, 
    STRING_AGG(DISTINCT p.coordinator_id::text, ',') AS project_managers,
    STRING_AGG(DISTINCT bao.id::text, ',') AS event_owners,
    STRING_AGG(DISTINCT bar.id::text, ',') AS event_reporters,
    STRING_AGG(DISTINCT bap.id::text, ',') AS event_providers
  FROM bird AS b
  INNER JOIN event AS e ON e.bird_id = b.id
  INNER JOIN project AS p ON p.id = e.project_id
  INNER JOIN bander AS bao ON bao.id = e.event_owner_id
  INNER JOIN bander AS bar ON bar.id = e.event_reporter_id
  INNER JOIN bander AS bap ON bap.id = e.event_provider_id
  GROUP BY b.id;

-- UPDATE GRANTS AFTER VIEWS ARE CREATED
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

-- UPDATE GRANTS AFTER VIEWS ARE CREATED
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
