/* Create materialized views to improve performance of complex and volumous queries */
/* ============================ */

-- ----------------------------------------------
-- Bander-birds matview
-- ----------------------------------------------
--Prereqs to drop bander_birds_matview
DROP VIEW IF EXISTS vw_advanced_search_events;
DROP MATERIALIZED VIEW IF EXISTS search_events_sort_timestamp;
DROP MATERIALIZED VIEW IF EXISTS search_events_sort_prefix_number;
DROP MATERIALIZED VIEW IF EXISTS search_events_sort_short_number;
DROP MATERIALIZED VIEW IF EXISTS search_events_sort_project_name;
DROP MATERIALIZED VIEW IF EXISTS search_events_sort_species_common_name;
DROP MATERIALIZED VIEW IF EXISTS search_events_sort_row_creation_timestamp;


DROP MATERIALIZED VIEW IF EXISTS bander_birds_matview;

CREATE MATERIALIZED VIEW bander_birds_matview
AS 
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

CREATE UNIQUE INDEX IF NOT EXISTS bander_birds_idx ON bander_birds_matview(bander_id, bird_id);

CREATE OR REPLACE FUNCTION rw_refresh_bander_birds_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY bander_birds_matview;
RETURN;
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------------
/* Unfiltered Search Events Ordered by event_timestamp Materialized View */
-- ----------------------------------------------

/* Create materialized views to improve performance of complex and volumous queries */
/* ============================ */

-- V2.0
DROP VIEW IF EXISTS vw_advanced_search_events;
DROP MATERIALIZED VIEW IF EXISTS advanced_search_events;

CREATE MATERIALIZED VIEW advanced_search_events 
  AS
SELECT 
  e.id, e.event_type, e.bird_id, e.row_creation_timestamp_, e.event_timestamp, e.event_reporter_id, e.event_provider_id, e.event_owner_id,
  e.event_banding_scheme, e.event_bird_situation, e.latitude, e.longitude, e.location_description, e.comments,
  p.id AS project_id, p.name AS project_name, p.default_moratorium_expiry,
  b.species_id, b.friendly_name, s.common_name_nznbbs, s.scientific_name_nznbbs, s.species_code_nznbbs,
  sg.id AS species_group_id, sg.name AS species_group_name,
  br.nznbbs_certification_number AS reporter_nznbbs_certification_number,
  bp.nznbbs_certification_number AS provider_nznbbs_certification_number,
  bo.nznbbs_certification_number AS owner_nznbbs_certification_number,
  cm.id AS characteristic_measurement_id, cm.characteristic_id AS characteristic_id, cm.value AS characteristic_measurement_value,
  jsonb_agg(json_build_object(
	  'mark_id',mc.mark_id,
	  'side', mc.side,
	  'position', mc.position,
	  'location_idx', mc.location_idx,
	  'mark_type', mc.mark_type,
    'mark_form', mc.mark_form,
	  'mark_material', mc.mark_material,
    'mark_fixing', mc.mark_fixing,
	  'colour', mc.colour,
	  'text_colour', mc.text_colour,
	  'alphanumeric_text', LOWER(mc.alphanumeric_text)
  )) AS agg_mc
FROM event AS e
INNER JOIN project AS p ON p.id = e.project_id
INNER JOIN bird AS b ON e.bird_id = b.id 
INNER JOIN species AS s ON b.species_id = s.id
INNER JOIN species_group_membership AS sgm ON sgm.species_id = s.id
INNER JOIN species_group AS sg ON sgm.group_id = sg.id
INNER JOIN bander AS br ON br.id = e.event_reporter_id
INNER JOIN bander AS bp ON bp.id = e.event_provider_id
INNER JOIN bander AS bo ON bo.id = e.event_owner_id
INNER JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
LEFT JOIN mark_configuration AS mc ON mc.event_id = e.id
WHERE e.event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER')
GROUP BY 
	e.id, p.id, b.species_id, b.friendly_name, s.common_name_nznbbs, s.scientific_name_nznbbs, s.species_code_nznbbs, sg.id, 
	br.nznbbs_certification_number, bp.nznbbs_certification_number, bo.nznbbs_certification_number,
	cm.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_as_event_id ON advanced_search_events(id);
CREATE INDEX IF NOT EXISTS idx_as_event_reporter_id ON advanced_search_events(event_reporter_id);
CREATE INDEX IF NOT EXISTS idx_as_event_provider_id ON advanced_search_events(event_provider_id);
CREATE INDEX IF NOT EXISTS idx_as_event_project_id ON advanced_search_events(project_id);
CREATE INDEX IF NOT EXISTS idx_as_event_timestamp ON advanced_search_events(event_timestamp);
CREATE INDEX IF NOT EXISTS idx_as_row_creation_timestamp ON advanced_search_events(row_creation_timestamp_);
CREATE INDEX IF NOT EXISTS idx_as_event_type ON advanced_search_events(event_type);
CREATE INDEX IF NOT EXISTS idx_as_event_banding_scheme ON advanced_search_events(event_banding_scheme);
CREATE INDEX IF NOT EXISTS idx_as_event_location_description ON advanced_search_events(location_description);
CREATE INDEX IF NOT EXISTS idx_as_event_latitude ON advanced_search_events(latitude);
CREATE INDEX IF NOT EXISTS idx_as_event_longitude ON advanced_search_events(longitude);
CREATE INDEX IF NOT EXISTS idx_as_event_latlong ON advanced_search_events(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_as_species_code_nznbbs ON advanced_search_events(species_code_nznbbs);
CREATE INDEX IF NOT EXISTS idx_as_bird_friendly_name ON advanced_search_events(friendly_name);
CREATE INDEX IF NOT EXISTS idx_as_common_name_nznbbs ON advanced_search_events(common_name_nznbbs);
CREATE INDEX IF NOT EXISTS idx_as_project_name ON advanced_search_events(project_name);


--Supporting view for JSONB array field searching
CREATE VIEW vw_advanced_search_events AS
  SELECT *
  FROM advanced_search_events ase, jsonb_array_elements(ase.agg_mc) obj;

CREATE OR REPLACE FUNCTION rw_refresh_advanced_search_events_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY advanced_search_events;
RETURN;
END;
$$ LANGUAGE plpgsql;

/* Unfiltered Search Events Materialized View Sorted by event_timestamp */

DROP MATERIALIZED VIEW IF EXISTS search_events_sort_timestamp;

CREATE MATERIALIZED VIEW search_events_sort_timestamp
AS 
SELECT
  --
    e.id AS id, event_type,
    e.event_banding_scheme AS event_banding_scheme, 
    e.event_reporter_id AS event_reporter_id, e.event_provider_id AS event_provider_id, e.event_owner_id AS event_owner_id,
    e.event_timestamp AS event_timestamp, e.event_bird_situation AS event_bird_situation,
  	dense_rank() over (order by e.event_timestamp, e.id)::integer AS pagination_idx,
    --
    b.id AS bird_id,
    --
    s.id AS species_id,
    --
    sg.id AS species_group_id,
    --
    ms.id AS mark_state_id, ms.state AS mark_state_state,
    --
    m.prefix_number AS mark_prefix_number, m.short_number AS mark_short_number, 
    --
    cm.id AS characteristic_measurement_id, cm.characteristic_id AS characteristic_id, cm.value AS characteristic_measurement_value,
    --
    p.id AS project_id, p.default_moratorium_expiry,
    --
    bb.bander_id AS previous_bander
  --
  FROM event AS e
    LEFT JOIN bird AS b ON b.id = e.bird_id
    LEFT JOIN species AS s ON s.id = b.species_id
    LEFT JOIN species_group_membership AS sgm ON sgm.species_id = s.id
    LEFT JOIN species_group AS sg ON sgm.group_id = sg.id
    LEFT JOIN mark_state AS ms ON ms.event_id = e.id
    LEFT JOIN mark AS m ON m.id = ms.mark_id
    LEFT JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
    LEFT JOIN project AS p ON p.id = e.project_id
    LEFT JOIN bander_birds_matview AS bb ON bb.bird_id = b.id
  WHERE event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER')
  ORDER BY event_timestamp
;

CREATE UNIQUE INDEX IF NOT EXISTS search_event_sort_timestamp_view_idx ON search_events_sort_timestamp(id,mark_state_id,characteristic_measurement_id, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_id ON search_events_sort_timestamp(id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_event_reporter_id ON search_events_sort_timestamp(event_reporter_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_bander_access_id ON search_events_sort_timestamp(pagination_idx, event_reporter_id, event_provider_id, event_owner_id, project_id, default_moratorium_expiry, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_event_timestamp ON search_events_sort_timestamp(event_timestamp);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_event_bird_situation ON search_events_sort_timestamp(event_bird_situation) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_pagination_idx ON search_events_sort_timestamp(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_bird_id ON search_events_sort_timestamp(bird_id) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_species_id ON search_events_sort_timestamp(species_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_mark_state_state ON search_events_sort_timestamp(mark_state_state);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_mark_prefix_number ON search_events_sort_timestamp(mark_prefix_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_mark_short_number ON search_events_sort_timestamp(mark_short_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_characteristic_measurement_value ON search_events_sort_timestamp(characteristic_measurement_value);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_project_id ON search_events_sort_timestamp(project_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_timestamp_project_moratorium_expiry ON search_events_sort_timestamp(default_moratorium_expiry);

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_timestamp_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY search_events_sort_timestamp;
RETURN;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------
/* Unfiltered Search Events Ordered by prefix_number Materialized View */
-- ----------------------------------------------

/* Create materialized views to improve performance of complex and volumous queries */
/* ============================ */

/* Unfiltered Search Events Materialized View Sorted by prefix_number */

DROP MATERIALIZED VIEW IF EXISTS search_events_sort_prefix_number;

CREATE MATERIALIZED VIEW search_events_sort_prefix_number
AS 
  SELECT 
  	--
    e.id AS id, event_type,
    e.event_banding_scheme AS event_banding_scheme, 
    e.event_reporter_id AS event_reporter_id, e.event_provider_id AS event_provider_id, e.event_owner_id AS event_owner_id,
    e.event_timestamp AS event_timestamp, e.event_bird_situation AS event_bird_situation,
  	dense_rank() over (order by m.prefix_number, m.short_number, e.id)::integer AS pagination_idx,
    --
    b.id AS bird_id,
    --
    s.id AS species_id,
    --
    sg.id AS species_group_id,
    --
    ms.id AS mark_state_id, ms.state AS mark_state_state,
    --
    m.prefix_number AS mark_prefix_number, m.short_number AS mark_short_number, 
    --
    cm.id AS characteristic_measurement_id, cm.value AS characteristic_measurement_value,
    --
    p.id AS project_id, p.default_moratorium_expiry,
    --
    bb.bander_id AS previous_bander
  --
  FROM event AS e
    LEFT JOIN bird AS b ON b.id = e.bird_id
    LEFT JOIN species AS s ON s.id = b.species_id
    LEFT JOIN species_group_membership AS sgm ON sgm.species_id = s.id
    LEFT JOIN species_group AS sg ON sgm.group_id = sg.id
    LEFT JOIN mark_state AS ms ON ms.event_id = e.id
    LEFT JOIN mark AS m ON m.id = ms.mark_id
    LEFT JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
    LEFT JOIN project AS p ON p.id = e.project_id
    LEFT JOIN bander_birds_matview AS bb ON bb.bird_id = b.id
  WHERE event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER')
  ORDER BY m.prefix_number, m.short_number
;

CREATE UNIQUE INDEX IF NOT EXISTS search_event_sort_prefix_number_view_idx ON search_events_sort_prefix_number(id,mark_state_id,characteristic_measurement_id, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_id ON search_events_sort_prefix_number(id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_event_reporter_id ON search_events_sort_prefix_number(event_reporter_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_bander_access_id ON search_events_sort_prefix_number(pagination_idx, event_reporter_id, event_provider_id, event_owner_id, project_id, default_moratorium_expiry, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_event_timestamp ON search_events_sort_prefix_number(event_timestamp);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_event_bird_situation ON search_events_sort_prefix_number(event_bird_situation) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_pagination_idx ON search_events_sort_prefix_number(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_bird_id ON search_events_sort_prefix_number(bird_id) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_species_id ON search_events_sort_prefix_number(species_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_mark_state_state ON search_events_sort_prefix_number(mark_state_state);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_mark_prefix_number ON search_events_sort_prefix_number(mark_prefix_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_mark_short_number ON search_events_sort_prefix_number(mark_short_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_characteristic_measurement_value ON search_events_sort_prefix_number(characteristic_measurement_value);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_project_id ON search_events_sort_prefix_number(project_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_prefix_number_project_moratorium_expiry ON search_events_sort_prefix_number(default_moratorium_expiry);

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_prefix_number_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY search_events_sort_prefix_number;
RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_prefix_number_matview_non_conc()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW search_events_sort_prefix_number;
RETURN;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------
/* Unfiltered Search Events Ordered by short_number Materialized View */
-- ----------------------------------------------

/* Create materialized views to improve performance of complex and volumous queries */
/* ============================ */

/* Unfiltered Search Events Materialized View Sorted by short_number */

DROP MATERIALIZED VIEW IF EXISTS search_events_sort_short_number;

CREATE MATERIALIZED VIEW search_events_sort_short_number
AS 
  SELECT 
  	--
    e.id AS id, event_type,
    e.event_banding_scheme AS event_banding_scheme, 
    e.event_reporter_id AS event_reporter_id, e.event_provider_id AS event_provider_id, e.event_owner_id AS event_owner_id,
    e.event_timestamp AS event_timestamp, e.event_bird_situation AS event_bird_situation,
  	dense_rank() over (order by m.short_number, m.prefix_number, e.id)::integer AS pagination_idx,
    --
    b.id AS bird_id,
    --
    s.id AS species_id,
    --
    sg.id AS species_group_id,
    --
    ms.id AS mark_state_id, ms.state AS mark_state_state,
    --
    m.prefix_number AS mark_prefix_number, m.short_number AS mark_short_number, 
    --
    cm.id AS characteristic_measurement_id, cm.value AS characteristic_measurement_value,
    --
    p.id AS project_id, p.default_moratorium_expiry,
    --
    bb.bander_id AS previous_bander
  --
  FROM event AS e
    LEFT JOIN bird AS b ON b.id = e.bird_id
    LEFT JOIN species AS s ON s.id = b.species_id
    LEFT JOIN species_group_membership AS sgm ON sgm.species_id = s.id
    LEFT JOIN species_group AS sg ON sgm.group_id = sg.id
    LEFT JOIN mark_state AS ms ON ms.event_id = e.id
    LEFT JOIN mark AS m ON m.id = ms.mark_id
    LEFT JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
    LEFT JOIN project AS p ON p.id = e.project_id
    LEFT JOIN bander_birds_matview AS bb ON bb.bird_id = b.id
  WHERE event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER')
  ORDER BY m.short_number, m.prefix_number
;

CREATE UNIQUE INDEX IF NOT EXISTS search_event_sort_short_number_view_idx ON search_events_sort_short_number(id,mark_state_id,characteristic_measurement_id, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_id ON search_events_sort_short_number(id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_event_reporter_id ON search_events_sort_short_number(event_reporter_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_bander_access_id ON search_events_sort_short_number(pagination_idx, event_reporter_id, event_provider_id, event_owner_id, project_id, default_moratorium_expiry, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_event_timestamp ON search_events_sort_short_number(event_timestamp);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_event_bird_situation ON search_events_sort_short_number(event_bird_situation) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_pagination_idx ON search_events_sort_short_number(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_bird_id ON search_events_sort_short_number(bird_id) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_species_id ON search_events_sort_short_number(species_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_mark_state_state ON search_events_sort_short_number(mark_state_state);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_mark_prefix_number ON search_events_sort_short_number(mark_prefix_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_mark_short_number ON search_events_sort_short_number(mark_short_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_characteristic_measurement_value ON search_events_sort_short_number(characteristic_measurement_value);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_project_id ON search_events_sort_short_number(project_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_short_number_project_moratorium_expiry ON search_events_sort_short_number(default_moratorium_expiry);

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_short_number_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY search_events_sort_short_number;
RETURN;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_short_number_matview_non_conc()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW search_events_sort_short_number;
RETURN;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------
/* Unfiltered Search Events Ordered by project_name Materialized View */
-- ----------------------------------------------

/* Create materialized views to improve performance of complex and volumous queries */
/* ============================ */

/* Unfiltered Search Events Materialized View Sorted by project_name */

DROP MATERIALIZED VIEW IF EXISTS search_events_sort_project_name;

CREATE MATERIALIZED VIEW search_events_sort_project_name
AS 
  SELECT 
  	--
    e.id AS id, event_type,
    e.event_banding_scheme AS event_banding_scheme, 
    e.event_reporter_id AS event_reporter_id, e.event_provider_id AS event_provider_id, e.event_owner_id AS event_owner_id,
    e.event_timestamp AS event_timestamp, e.event_bird_situation AS event_bird_situation,
  	dense_rank() over (order by p.name, e.id)::integer AS pagination_idx,
    --
    b.id AS bird_id,
    --
    s.id AS species_id,
    --
    sg.id AS species_group_id,
    --
    ms.id AS mark_state_id, ms.state AS mark_state_state,
    --
    m.prefix_number AS mark_prefix_number, m.short_number AS mark_short_number, 
    --
    cm.id AS characteristic_measurement_id, cm.value AS characteristic_measurement_value,
    --
    p.id AS project_id, p.default_moratorium_expiry,
    --
    bb.bander_id AS previous_bander
  --
  FROM event AS e
    LEFT JOIN bird AS b ON b.id = e.bird_id
    LEFT JOIN species AS s ON s.id = b.species_id
    LEFT JOIN species_group_membership AS sgm ON sgm.species_id = s.id
    LEFT JOIN species_group AS sg ON sgm.group_id = sg.id
    LEFT JOIN mark_state AS ms ON ms.event_id = e.id
    LEFT JOIN mark AS m ON m.id = ms.mark_id
    LEFT JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
    LEFT JOIN project AS p ON p.id = e.project_id
    LEFT JOIN bander_birds_matview AS bb ON bb.bird_id = b.id
  WHERE event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER')
  ORDER BY p.name
;

CREATE UNIQUE INDEX IF NOT EXISTS search_event_sort_project_name_view_idx ON search_events_sort_project_name(id,mark_state_id,characteristic_measurement_id, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_id ON search_events_sort_project_name(id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_event_reporter_id ON search_events_sort_project_name(event_reporter_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_bander_access_id ON search_events_sort_project_name(pagination_idx, event_reporter_id, event_provider_id, event_owner_id, project_id, default_moratorium_expiry, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_event_timestamp ON search_events_sort_project_name(event_timestamp);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_event_bird_situation ON search_events_sort_project_name(event_bird_situation) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_pagination_idx ON search_events_sort_project_name(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_bird_id ON search_events_sort_project_name(bird_id) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_species_id ON search_events_sort_project_name(species_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_mark_state_state ON search_events_sort_project_name(mark_state_state);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_mark_prefix_number ON search_events_sort_project_name(mark_prefix_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_mark_short_number ON search_events_sort_project_name(mark_short_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_characteristic_measurement_value ON search_events_sort_project_name(characteristic_measurement_value);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_project_id ON search_events_sort_project_name(project_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_project_name_project_moratorium_expiry ON search_events_sort_project_name(default_moratorium_expiry);

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_project_name_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY search_events_sort_project_name;
RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_project_name_matview_non_conc()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW search_events_sort_project_name;
RETURN;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------
/* Unfiltered Search Events Ordered by species_common_name_nznbbs Materialized View */
-- ----------------------------------------------

/* Create materialized views to improve performance of complex and volumous queries */
/* ============================ */

/* Unfiltered Search Events Materialized View Sorted by species_common_name_nznbbs */

DROP MATERIALIZED VIEW IF EXISTS search_events_sort_species_common_name;

CREATE MATERIALIZED VIEW search_events_sort_species_common_name
AS 
  SELECT 
  	--
    e.id AS id, event_type,
    e.event_banding_scheme AS event_banding_scheme, 
    e.event_reporter_id AS event_reporter_id, e.event_provider_id AS event_provider_id, e.event_owner_id AS event_owner_id,
    e.event_timestamp AS event_timestamp, e.event_bird_situation AS event_bird_situation,
  	dense_rank() over (order by s.common_name_nznbbs, e.id)::integer AS pagination_idx,
    --
    b.id AS bird_id,
    --
    s.id AS species_id, s.common_name_nznbbs AS common_name_nznbbs,
    --
    sg.id AS species_group_id,
    --
    ms.id AS mark_state_id, ms.state AS mark_state_state,
    --
    m.prefix_number AS mark_prefix_number, m.short_number AS mark_short_number, 
    --
    cm.id AS characteristic_measurement_id, cm.value AS characteristic_measurement_value,
    --
    p.id AS project_id, p.default_moratorium_expiry,
    --
    bb.bander_id AS previous_bander
    --
  FROM event AS e
    LEFT JOIN bird AS b ON b.id = e.bird_id
    LEFT JOIN species AS s ON s.id = b.species_id
    LEFT JOIN species_group_membership AS sgm ON sgm.species_id = s.id
    LEFT JOIN species_group AS sg ON sgm.group_id = sg.id
    LEFT JOIN mark_state AS ms ON ms.event_id = e.id
    LEFT JOIN mark AS m ON m.id = ms.mark_id
    LEFT JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
    LEFT JOIN project AS p ON p.id = e.project_id
    LEFT JOIN bander_birds_matview AS bb ON bb.bird_id = b.id
  WHERE event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER')
  ORDER BY s.common_name_nznbbs
;

CREATE UNIQUE INDEX IF NOT EXISTS search_event_sort_species_common_name_view_idx ON search_events_sort_species_common_name(id,mark_state_id,characteristic_measurement_id, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_id ON search_events_sort_species_common_name(id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_event_reporter_id ON search_events_sort_species_common_name(event_reporter_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_bander_access_id ON search_events_sort_species_common_name(pagination_idx, event_reporter_id, event_provider_id, event_owner_id, project_id, default_moratorium_expiry, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_event_timestamp ON search_events_sort_species_common_name(event_timestamp);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_event_bird_situation ON search_events_sort_species_common_name(event_bird_situation) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_pagination_idx ON search_events_sort_species_common_name(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_bird_id ON search_events_sort_species_common_name(bird_id) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_species_id ON search_events_sort_species_common_name(species_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_mark_state_state ON search_events_sort_species_common_name(mark_state_state);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_mark_prefix_number ON search_events_sort_species_common_name(mark_prefix_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_mark_short_number ON search_events_sort_species_common_name(mark_short_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_characteristic_measurement_value ON search_events_sort_species_common_name(characteristic_measurement_value);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_project_id ON search_events_sort_species_common_name(project_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_species_common_name_project_moratorium_expiry ON search_events_sort_species_common_name(default_moratorium_expiry);

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_species_common_name_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY search_events_sort_species_common_name;
RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_species_common_name_matview_non_conc()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW search_events_sort_species_common_name;
RETURN;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------
/* Unfiltered Search Events Ordered by event_row_creation_timestamp_ Materialized View */
-- ----------------------------------------------

/* Create materialized views to improve performance of complex and volumous queries */
/* ============================ */

/* Unfiltered Search Events Materialized View Sorted by event_row_creation_timestamp_ */

DROP MATERIALIZED VIEW IF EXISTS search_events_sort_row_creation_timestamp;

CREATE MATERIALIZED VIEW search_events_sort_row_creation_timestamp
AS 
  SELECT 
  	--
    e.id AS id, event_type,
    e.event_banding_scheme AS event_banding_scheme, 
    e.event_reporter_id AS event_reporter_id, e.event_provider_id AS event_provider_id, e.event_owner_id AS event_owner_id,
    e.event_timestamp AS event_timestamp, e.event_bird_situation AS event_bird_situation,
  	dense_rank() over (order by e.row_creation_timestamp_, e.id)::integer AS pagination_idx,
    --
    b.id AS bird_id,
    --
    s.id AS species_id, s.common_name_nznbbs AS common_name_nznbbs,
    --
    sg.id AS species_group_id,
    --
    ms.id AS mark_state_id, ms.state AS mark_state_state,
    --
    m.prefix_number AS mark_prefix_number, m.short_number AS mark_short_number, 
    --
    cm.id AS characteristic_measurement_id, cm.value AS characteristic_measurement_value,
    --
    p.id AS project_id, p.default_moratorium_expiry,
    --
    bb.bander_id AS previous_bander
    --
  FROM event AS e
    LEFT JOIN bird AS b ON b.id = e.bird_id
    LEFT JOIN species AS s ON s.id = b.species_id
    LEFT JOIN species_group_membership AS sgm ON sgm.species_id = s.id
    LEFT JOIN species_group AS sg ON sgm.group_id = sg.id
    LEFT JOIN mark_state AS ms ON ms.event_id = e.id
    LEFT JOIN mark AS m ON m.id = ms.mark_id
    LEFT JOIN characteristic_measurement AS cm ON cm.event_id = e.id AND cm.characteristic_id = 43
    LEFT JOIN project AS p ON p.id = e.project_id
    LEFT JOIN bander_birds_matview AS bb ON bb.bird_id = b.id
  WHERE event_type NOT IN ('NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER')
  ORDER BY e.row_creation_timestamp_
;

CREATE UNIQUE INDEX IF NOT EXISTS search_event_sort_row_creation_timestamp_view_idx ON search_events_sort_row_creation_timestamp(id,mark_state_id,characteristic_measurement_id, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_id ON search_events_sort_row_creation_timestamp(id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_event_reporter_id ON search_events_sort_row_creation_timestamp(event_reporter_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_bander_access_id ON search_events_sort_row_creation_timestamp(pagination_idx, event_reporter_id, event_provider_id, event_owner_id, project_id, default_moratorium_expiry, previous_bander);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_event_timestamp ON search_events_sort_row_creation_timestamp(event_timestamp);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_event_bird_situation ON search_events_sort_row_creation_timestamp(event_bird_situation) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_pagination_idx ON search_events_sort_row_creation_timestamp(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_bird_id ON search_events_sort_row_creation_timestamp(bird_id) where bird_id is not null;
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_species_id ON search_events_sort_row_creation_timestamp(species_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_mark_state_state ON search_events_sort_row_creation_timestamp(mark_state_state);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_mark_prefix_number ON search_events_sort_row_creation_timestamp(mark_prefix_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_mark_short_number ON search_events_sort_row_creation_timestamp(mark_short_number);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_characteristic_measurement_value ON search_events_sort_row_creation_timestamp(characteristic_measurement_value);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_project_id ON search_events_sort_row_creation_timestamp(project_id);
CREATE INDEX IF NOT EXISTS idx_search_event_sort_row_creation_timestamp_project_moratorium_expiry ON search_events_sort_row_creation_timestamp(default_moratorium_expiry);

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_row_creation_timestamp_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY search_events_sort_row_creation_timestamp;
RETURN;
END;
$$ LANGUAGE plpgsql;


-- Project - Event count

CREATE OR REPLACE FUNCTION rw_refresh_search_event_sort_row_creation_timestamp_matview_non_conc()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW search_events_sort_row_creation_timestamp;
RETURN;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------
/*  */
-- ----------------------------------------------

/* Create materialized views to improve performance of complex and volumous queries/counts */
/* ============================ */

/* Unfiltered Project Event Count Materialized View */

DROP MATERIALIZED VIEW IF EXISTS project_event_counts_matview;

CREATE MATERIALIZED VIEW project_event_counts_matview
AS 
  SELECT 
  	--
    p.id, 
    (select count(e.id) from event AS e 
	    where p.id = e.project_id )::integer AS project_event_count
  FROM project AS p
  GROUP BY p.id
;

CREATE UNIQUE INDEX IF NOT EXISTS project_event_counts_matview_project_id_idx ON project_event_counts_matview(id);

CREATE OR REPLACE FUNCTION rw_refresh_project_event_counts_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY project_event_counts_matview;
RETURN;
END;
$$ LANGUAGE plpgsql;


/* Create materialized views to improve pagination performance for marks */
/* ============================ */

/* Unfiltered Project Event Count Materialized View */
-- DEPENDENT VIEWS NEED TO BE REMOVED FIRST!
DROP VIEW IF EXISTS vw_mark_latest;
DROP VIEW IF EXISTS vw_mark_latest_numeric_short_number;
DROP VIEW IF EXISTS vw_most_recent_mark_state;
DROP VIEW IF EXISTS vw_most_recent_mark_allocation;
DROP VIEW IF EXISTS vw_distinct_prefix_numbers;
DROP VIEW IF EXISTS vw_admin_mark_aggregation;
DROP VIEW IF EXISTS vw_mark_aggregation; /* Included for dependency*/


DROP VIEW IF EXISTS vw_bander_mark_last_short_number;
CREATE VIEW vw_bander_mark_last_short_number AS
  WITH msn AS 
  (
    SELECT prefix_number, ma.bander_id, MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint) AS max_short_number 
    FROM mark AS m
    INNER JOIN mark_allocation AS ma ON ma.mark_id = m.id AND ma.is_current = TRUE
    GROUP BY prefix_number, bander_id
  )
  SELECT msn.prefix_number, m.short_number AS max_short_number, msn.bander_id
  FROM msn
  INNER JOIN mark AS m ON msn.prefix_number = m.prefix_number AND msn.max_short_number = NULLIF(regexp_replace(m.short_number, '\D', '', 'g'), '')::bigint
;

-- 

DROP MATERIALIZED VIEW IF EXISTS mark_pagination_sort_band_number_matview;

CREATE MATERIALIZED VIEW mark_pagination_sort_band_number_matview
AS 
  SELECT 
  	--
    m.id,
    m.prefix_number,
    m.short_number,
    NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint AS short_number_numeric,
    row_number() over (order by m.prefix_number ASC, NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint ASC)::integer AS pagination_idx
	FROM mark as m
;

CREATE UNIQUE INDEX IF NOT EXISTS mark_pagination_sort_band_number_matview_pagination_idx ON mark_pagination_sort_band_number_matview(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_mark_pagination_sort_band_number_matview_mark_id ON mark_pagination_sort_band_number_matview(id);
CREATE INDEX IF NOT EXISTS idx_mark_pagination_sort_band_number_matview_paginated_prefix ON mark_pagination_sort_band_number_matview(pagination_idx, prefix_number);

CREATE OR REPLACE FUNCTION rw_refresh_mark_pagination_sort_band_number_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mark_pagination_sort_band_number_matview;
RETURN;
END;
$$ LANGUAGE plpgsql;


DROP MATERIALIZED VIEW IF EXISTS mark_latest_matview;

CREATE MATERIALIZED VIEW mark_latest_matview
AS 
  SELECT 
  	--
    m.id,
    m.prefix_number,
    m.short_number,
    NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint AS short_number_numeric,
    ma.bander_id,
    ms.state,
    row_number() over (order by m.prefix_number ASC, NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint ASC)::integer AS pagination_idx
	FROM mark as m
  	INNER JOIN mark_allocation AS ma ON ma.mark_id = m.id
    INNER JOIN mark_state AS ms ON ms.mark_id = m.id
  	WHERE ms.is_current= TRUE AND ma.is_current = TRUE
;

CREATE UNIQUE INDEX IF NOT EXISTS mark_latest_matview_pagination_idx ON mark_latest_matview(pagination_idx);
CREATE INDEX IF NOT EXISTS idx_mark_latest_matview_mark_id ON mark_latest_matview(id);
CREATE INDEX IF NOT EXISTS idx_mark_latest_matview_bander_id ON mark_latest_matview(bander_id);
CREATE INDEX IF NOT EXISTS idx_mark_latest_matview_state ON mark_latest_matview(state);

CREATE OR REPLACE FUNCTION rw_refresh_mark_latest_matview()
RETURNS void
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mark_latest_matview;
RETURN;
END;
$$ LANGUAGE plpgsql;

-- Have replicated these views here because they are dependent on the materialized view above
-- ----------------------------------------------
/* Aggregated Mark Last Short numbers */
-- ----------------------------------------------
-- Needed together given depedency

DROP VIEW IF EXISTS vw_mark_last_short_number;
CREATE VIEW vw_mark_last_short_number AS
  SELECT prefix_number, MAX(NULLIF(regexp_replace(short_number, '\D', '', 'g'), '')::bigint) AS max_short_number 
  FROM mark AS m
	GROUP BY prefix_number
;

  -- ----------------------------------------------
/* View of latest mark details */
-- ----------------------------------------------
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
/* View of the marks table with numeric short numbers where available (support from/to searching)*/
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
/* View of latest mark details */
-- ----------------------------------------------
DROP VIEW IF EXISTS vw_mark_aggregation;

CREATE VIEW vw_mark_aggregation AS
  SELECT vma.bander_id, m.prefix_number, 
  COUNT(vma.mark_id)::integer AS number_of_bands, 
  vlsn.max_short_number AS last_short_number
  FROM mark_allocation AS vma
  INNER JOIN mark_state as ms ON ms.mark_id = vma.mark_id
  INNER JOIN mark AS m ON m.id = vma.mark_id
  INNER JOIN vw_bander_mark_last_short_number AS vlsn ON vlsn.prefix_number = m.prefix_number AND vlsn.bander_id = vma.bander_id
  WHERE ms.state IN ('NEW', 'ALLOCATED', 'RETURNED') AND ms.is_current = TRUE AND vma.is_current = TRUE
  GROUP BY vlsn.max_short_number, m.prefix_number, vma.bander_id
  ORDER BY m.prefix_number;

DROP VIEW IF EXISTS vw_admin_mark_aggregation;

CREATE VIEW vw_admin_mark_aggregation AS
  SELECT vma.bander_id, m.prefix_number, 
  COUNT(vma.mark_id)::integer AS number_of_bands, 
  vlsn.max_short_number AS last_short_number
  FROM mark_allocation AS vma
  INNER JOIN mark_state as ms ON ms.mark_id = vma.mark_id
  INNER JOIN mark AS m ON m.id = vma.mark_id
  INNER JOIN vw_mark_last_short_number AS vlsn ON vlsn.prefix_number = m.prefix_number
  WHERE ms.state IN ('NEW', 'ALLOCATED', 'RETURNED') AND ms.is_current = TRUE AND vma.is_current = TRUE
  GROUP BY vlsn.max_short_number, m.prefix_number, vma.bander_id
  ORDER BY m.prefix_number;

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