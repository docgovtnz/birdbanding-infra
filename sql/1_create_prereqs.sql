/* Create schema pre-requisites */
/* ============================ */

/* 
Enable postGIS
Enable postGIS if you want the Aurora/postgreSQL RDS instance
to work with spatial data. Typically, this should not be
required since we should offload all GIS type functions to
the GIS team and consume their services to perform such functions.
*/

/* NOTE: Must be logged in as superuser! */
CREATE extension IF NOT EXISTS "postgis";
CREATE extension IF NOT EXISTS "fuzzystrmatch";
CREATE extension IF NOT EXISTS "postgis_tiger_geocoder";
CREATE extension IF NOT EXISTS "postgis_topology";
CREATE EXTENSION IF NOT EXISTS aws_s3 CASCADE;

ALTER SCHEMA tiger OWNER TO rds_superuser;
ALTER SCHEMA tiger_data OWNER TO rds_superuser;
ALTER SCHEMA topology OWNER TO rds_superuser;
-- Required to add NZMG Coordinate transform from 
ALTER TABLE public.spatial_ref_sys OWNER TO rds_superuser;

CREATE OR REPLACE FUNCTION exec(text) RETURNS text language plpgsql volatile AS $f$ BEGIN EXECUTE $1; RETURN $1; END; $f$;

SELECT exec('ALTER TABLE ' || quote_ident(s.nspname) || '.' || quote_ident(s.relname) || ' OWNER TO rds_superuser;')
  FROM (
    SELECT nspname, relname
    FROM pg_class c JOIN pg_namespace n ON (c.relnamespace = n.oid) 
    WHERE nspname in ('tiger','topology') AND
    relkind IN ('r','S','v') ORDER BY relkind = 'S')
s;

/* Perhaps not strictly necessary, but will avoid issues down the track, I think */
GRANT SELECT, INSERT ON TABLE public.spatial_ref_sys TO PUBLIC;
GRANT ALL ON TABLE public.geometry_columns TO PUBLIC;
GRANT ALL ON TABLE public.spatial_ref_sys TO PUBLIC;
GRANT ALL ON TABLE public.raster_columns TO PUBLIC;
GRANT ALL ON TABLE public.raster_overviews TO PUBLIC;

/* 
Add ability to auto-generate UUIDs if needed.
Once installed, we can generate IDs using uuid_generate_v4();
*/
CREATE extension IF NOT EXISTS "uuid-ossp";

/* 
Configure NZMG coordinate projection to use https://epsg.io/27200 POSTGis definition
*/
UPDATE spatial_ref_sys SET auth_name = 'EPSG', auth_srid = 27200, proj4text = '+proj=nzmg +lat_0=-41 +lon_0=173 +x_0=2510000 +y_0=6023150 +ellps=intl +towgs84=59.47,-5.04,187.44,0.47,-0.1,1.024,-4.5993 +units=m +no_defs ', srtext = 'PROJCS["NZGD49 / New Zealand Map Grid",GEOGCS["NZGD49",DATUM["New_Zealand_Geodetic_Datum_1949",SPHEROID["International 1924",6378388,297,AUTHORITY["EPSG","7022"]],TOWGS84[59.47,-5.04,187.44,0.47,-0.1,1.024,-4.5993],AUTHORITY["EPSG","6272"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4272"]],PROJECTION["New_Zealand_Map_Grid"],PARAMETER["latitude_of_origin",-41],PARAMETER["central_meridian",173],PARAMETER["false_easting",2510000],PARAMETER["false_northing",6023150],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","27200"]]' where srid = 27200; 

/* 
Add function to automatically supply timestamps for
row updates and creations
*/
CREATE OR REPLACE FUNCTION update_row_modified_timestamp()
/* -------------------------------------------------------- */
RETURNS TRIGGER 
AS 
$$
BEGIN
    IF TG_OP = 'INSERT' THEN 
        NEW.row_creation_timestamp_ = CURRENT_TIMESTAMP(0);
        NEW.row_creation_user_ = CURRENT_USER;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.row_update_timestamp_ = CURRENT_TIMESTAMP(0);
        NEW.row_update_user_ = CURRENT_USER;
        RETURN NEW;
    END IF;
END;
$$ 
LANGUAGE 'plpgsql';

/* 
Add function to automatically update geography column from lat/lon, nztm and nzmg 
-- (for bander events who understand the fundamentals of coordinate systems)
*/
CREATE OR REPLACE FUNCTION update_location_geography()
/* -------------------------------------------------------- */
RETURNS TRIGGER 
AS 
$$
BEGIN
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude),4326);
        RETURN NEW;
    ELSIF NEW.user_northing IS NOT NULL AND NEW.user_easting IS NOT NULL AND NEW.user_coordinate_system = 'NZTM' THEN
        NEW.latitude = ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(NEW.user_easting, NEW.user_northing), 2193), 4326));
        NEW.longitude = ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(NEW.user_easting, NEW.user_northing), 2193), 4326));
        NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude),4326);
        RETURN NEW;
    ELSIF NEW.user_northing IS NOT NULL AND NEW.user_easting IS NOT NULL AND NEW.user_coordinate_system = 'NZMG' THEN
        NEW.latitude = ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(NEW.user_easting, NEW.user_northing), 27200), 4326));
        NEW.longitude = ST_X(ST_Transform(ST_SetSRID(ST_MakePoint(NEW.user_easting, NEW.user_northing), 27200), 4326));
        NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude),4326);
        RETURN NEW;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ 
LANGUAGE 'plpgsql';

/* 
Add function to automatically update geography column from lat/lon
-- Lat/long only specifically developed to handle public sightings (where other coordinate systems aren't supported)
*/
CREATE OR REPLACE FUNCTION update_location_geography_wgs84()
/* -------------------------------------------------------- */
RETURNS TRIGGER 
AS 
$$
BEGIN
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude),4326);
        RETURN NEW;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ 
LANGUAGE 'plpgsql';

/* TYPES 
NOTE: This is awesome - we can return all the possible values of an
Enum using the following query:

SELECT unnest(enum_range(NULL::<enum_name>))::text as <enum_name>_values;

This allows us to return the possible values if needed, i.e. as part of an
API GET request
*/

/* Enumerated type indicating NZNBBS Code level */
DROP TYPE IF EXISTS enum_event_code;
CREATE TYPE enum_event_code AS ENUM (
  '1 - First marking',
  'Z - Foreign Scheme band/mark',
  '2A - Resighted without being caught',
  '2B - Recaptured (but not re-marked)',
  '2C - Technology assisted retrap',
  '2D - Translocation release',
  '3 - Add/Change/Remove mark',
  'X - Dead: Recovery',
  '0 - Stock Held',
  'L - Lost band / destroyed / used for training.',
  'T - Transferred to another L3 bander',
  'R - Returned band (unused) to Banding Office',
  'P - Practice bands: issued specifically for training',
  'U - Used band returned to Banding Office',
  'Y - Other use',
  'C - Captive/rehab history'
);

/* Enumerated type indicating competency level */
DROP TYPE IF EXISTS enum_competency_level;
CREATE TYPE enum_competency_level AS ENUM ('L1', 'L2', 'L3');

/* Enumerated type indicating invitation state */
DROP TYPE IF EXISTS enum_invitation_state;
CREATE TYPE enum_invitation_state AS ENUM ('PENDING', 'ACCEPTED', 'DECLINED');

/* Enumerated type indicating event type. */
DROP TYPE IF EXISTS enum_event_type;
CREATE TYPE enum_event_type AS ENUM ('FIRST_MARKING_IN_HAND','SIGHTING_BY_PERSON', 'IN_HAND', 'IN_HAND_PRE_CHANGE', 'IN_HAND_POST_CHANGE', 'RECORDED_BY_TECHNOLOGY', 'NEW_MARK', 'LOST', 'FOUND', 'PRACTICE', 'OTHER', 'TRANSFER');

/* Enumerated type indicating event state. */
DROP TYPE IF EXISTS enum_event_state;
CREATE TYPE enum_event_state AS ENUM ('AWAITING_REVIEW', 'VALID', 'INVALID', 'TRANSFER_REQUEST', 'TRANSFER_ACCEPTED', 'TRANSFER_REJECTED');

/* Enumerated type indicating event state. */
DROP TYPE IF EXISTS enum_public_event_status;
CREATE TYPE enum_public_event_status AS ENUM ('RAW', 'REJECTED', 'VERIFIED');

/* Enumerated type indicating event state. */
DROP TYPE IF EXISTS enum_media_upload_status;
CREATE TYPE enum_media_upload_status AS ENUM ('REQUESTED', 'RAW', 'AVAILABLE');

/* Enumerated type indicating event banding scheme. */
DROP TYPE IF EXISTS enum_event_banding_scheme;
CREATE TYPE enum_event_banding_scheme AS ENUM('NZ_NON_GAMEBIRD', 'NZ_GAMEBIRD', 'FOREIGN');

/* Enumerated type indicating species taxonomic status. */
DROP TYPE IF EXISTS enum_species_taxonomic_status;
CREATE TYPE enum_species_taxonomic_status AS ENUM ('CURRENT', 'SYNONYM');

/* Enumerated type indicating event timestamp accuracy */
DROP TYPE IF EXISTS enum_event_event_timestamp_accuracy;
CREATE TYPE enum_event_event_timestamp_accuracy AS ENUM ('D', 'M', 'Y', 'U');


/* Enumerated type indicating event timestamp accuracy */
DROP TYPE IF EXISTS enum_event_capture_type;
CREATE TYPE enum_event_capture_type AS ENUM 
  (
    'CAUGHT_BY_HAND', 'CAPTURED_IN_A_NATURAL_NEST', 'CAPTURED_IN_A_NEST_BOX', 'CAUGHT_BY_HAND_NET' ,'CAUGHT_BY_CANNON_NET' ,'CAUGHT_IN_MIST_NET',
    'CAUGHT_IN_FISHING_NET', 'CAUGHT_BY_NOOSE_MAT', 'CAUGHT_BY_CLAP_TRAP', 'CAUGHT_BY_WHOOSH_NET', 'CAUGHT_BY_POTTER_TRAP', 'CAUGHT_BY_PULL_ACTIVATED_DROP_TRAP',
    'CAUGHT_BY_FUNNEL_TRAP','CAUGHT_IN_PULL_ACTIVATED_LEG_NOOSE' ,'CAUGHT_BY_NECK_HOOP_OR_CROOK' , 'CAUGHT_BY_NOOSE_HAT_OR_BAL_CHATRI', 'CAUGHT_BY_NET_GUN',
    'CAUGHT_BY_CAGE_TRAP' , 'CAPTURED_AT_FEEDER', 'OTHER'
  );

/* Enumerated type indicating download status */
DROP TYPE IF EXISTS enum_download_status;
CREATE TYPE enum_download_status AS ENUM (
  'REQUEST', 
  'REQUEST_PENDING_APPROVAL',
  'READY_FOR_DOWNLOAD',
  'START',
  'IN_PROGRESS',
  'AVAILABLE_FOR_DOWNLOAD',
  'DOWNLOAD_FAILED'
);


/* Enumerated type indicating event user input coordinate system */
/* Used to carry out transforms on insertion and record which coordinate systems are being submitted with new data */
DROP TYPE IF EXISTS enum_event_bird_situation;
CREATE TYPE enum_event_bird_situation AS ENUM ('WILD', 'CAPTIVE', 'SOURCE_SITE', 'RELEASE_SITE');

/* Enumerated type indicating event user input coordinate system */
/* Used to carry out transforms on insertion and record which coordinate systems are being submitted with new data */
DROP TYPE IF EXISTS enum_event_user_coordinate_system;
CREATE TYPE enum_event_user_coordinate_system AS ENUM ('WGS84', 'NZTM', 'NZMG');

/* Enumerated type indicating characteristic datatype for casting */
DROP TYPE IF EXISTS enum_characteristic_datatype;
CREATE TYPE enum_characteristic_datatype AS ENUM ('TEXT', 'NUMERIC', 'DATETIME', 'ARRAY');

/* Enumerated type indicating bander state */
DROP TYPE IF EXISTS enum_bander_state;
CREATE TYPE enum_bander_state AS ENUM ('LOCKED', 'SUSPENDED', 'ACTIVE', 'INACTIVE');

/* Enumerated type indicating mark attachment sides */
DROP TYPE IF EXISTS enum_mark_configuration_side;
CREATE TYPE enum_mark_configuration_side AS ENUM ('LEFT', 'RIGHT');

/* Enumerated type indicating mark attachment position */
DROP TYPE IF EXISTS enum_mark_configuration_position;
CREATE TYPE enum_mark_configuration_position AS ENUM ('TIBIA', 'TARSUS');

/* Enumerated type indicating mark type*/
DROP TYPE IF EXISTS enum_mark_type;
CREATE TYPE enum_mark_type AS ENUM (
  'LEG_BAND',
  'LEG_TRANSPONDER',
  'INSERTED_TRANSPONDER',
  'WEB',
  'JESS',
  'GPS',
  'TDR',
  'GLS',
  'FLIPPER',
  'WING',
  'TRANSMITTER',
  'OTHER'
  );

/* Enumerated type indicating mark materials*/
DROP TYPE IF EXISTS enum_mark_material;
CREATE TYPE enum_mark_material AS ENUM ('METAL', 'ACETATE', 'ACRYLIC', 'DARVIC', 'CELLULOID', 'PLASTIC_UNSPECIFIED', 'OTHER');

/* Enumerated type indicating mark materials*/
DROP TYPE IF EXISTS enum_mark_form;
CREATE TYPE enum_mark_form AS ENUM 
  (
    'BUTT', 'BUTT_HALF_METAL', 'WRAPAROUND_1', 'WRAPAROUND_1_5', 'WRAPAROUND_1_75', 
    'WRAPAROUND_2', 'WRAPAROUND_UNKNOWN', 'SPIRAL', 'FLAG', 'OTHER'
  );

/* Enumerated type indicating mark fixing*/
DROP TYPE IF EXISTS enum_mark_fixing;
CREATE TYPE enum_mark_fixing AS ENUM 
  (
    'GLUE', 'THF', 'SUPERGLUE', 'PIPE_CEMENT', 'SELLEYS_PLASTIC_FIX_2_STEP',
    'SOLDER', 'DOUBLE_SIDED_TAPE', 'SOLVENT', 'OTHER'
  );
    
/* Enumerated type indicating mark state */
DROP TYPE IF EXISTS enum_mark_state;
CREATE TYPE enum_mark_state AS ENUM ('NEW', 'ALLOCATED', 'ATTACHED', 'DETACHED', 'RETURNED', 'PRACTICE', 'LOST', 'RETURNED_USED', 'OTHER');

/* Enumerated type indicating mark colour */
DROP TYPE IF EXISTS enum_mark_colour;
CREATE TYPE enum_mark_colour AS ENUM (
  'BLACK',
  'WHITE',
  'GREY',
  'RED',
  'ORANGE',
  'PALE_ORANGE',
  'FLUORESCENT_ORANGE',
  'YELLOW',
  'PALE_PINK',
  'PINK',
  'FLUORESCENT_PINK',
  'CRIMSON_PINK',
  'FLUORESCENT_PURPLE',
  'LIGHT_PURPLE',
  'PURPLE',
  'PALE_BLUE',
  'FLUORESCENT_BLUE',
  'LIGHT_BLUE',
  'BLUE',
  'DARK_BLUE', 
  'FLUORESCENT_GREEN',
  'LIME_GREEN',
  'PALE_GREEN',
  'GREEN',
  'DARK_GREEN',
  'BROWN',
  'BLUE_STRIPED_PINK',
  'GREEN_STRIPED_PURPLE',
  'RED_STRIPED_WHITE',
  'PINK_STRIPED_WHITE',
  'BLUE_STRIPED_YELLOW',
  'OTHER'
);

DROP TYPE IF EXISTS enum_endorsement;
CREATE TYPE enum_endorsement AS ENUM (
  'Mist-netting',
  'Mist-netting waterfowl',
  'Cannon-netting',
  'Net gun',
  'Pullus',
  'Transponder insertion'
);

/* Enumerated type indicating project state */
DROP TYPE IF EXISTS enum_project_state;
CREATE TYPE enum_project_state AS ENUM ('AWAITING_APPROVAL', 'INACTIVE', 'ACTIVE');

DROP TYPE IF EXISTS enum_status_code;
CREATE TYPE enum_status_code AS ENUM (
  'DEAD_RECENT',
  'DEAD_UNSPECIFIED',
  'DEAD_NOT_RECENT',
  'UNKNOWN',
  'UNKNOWN_BAND_ONLY',
  'ALIVE'
);

DROP TYPE IF EXISTS enum_condition_code;
CREATE TYPE enum_condition_code AS ENUM (
  '0', '1', '2', '3', '4', '5', '99'
);

DROP TYPE IF EXISTS enum_condition_value;
CREATE TYPE enum_condition_value AS ENUM (
  'GOOD', 'POOR', 'INJURED_SICK', 'REHABILITATED', 'ARTIFICIALLY_REARED', 'OTHER'
);

DROP TYPE IF EXISTS enum_region;
CREATE TYPE enum_region AS ENUM (
    'NORTHLAND', 'AUCKLAND', 'WAIKATO',
    'BAY OF PLENTY', 'GISBORNE', 'HAWKE''S BAY',
    'TARANAKI', 'MANAWATU-WHANGANUI', 'WELLINGTON',
    'WEST COAST', 'CANTERBURY', 'OTAGO',
    'SOUTHLAND', 'TASMAN', 'NELSON',
    'MARLBOROUGH', 'CHATHAMS', 'SUBANTARCTIC ISLANDS',
    'PACIFIC ISLANDS', 'AT SEA', 'AUSTRALIA', 'OTHER'
);

DROP TYPE IF EXISTS enum_bird_age;
CREATE TYPE enum_bird_age AS ENUM (
  'a', 'j', 'p', 'u',
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10',
  '11', '12', '13', '14', '15', '16', '17', '18', '19', '20',
  '21', '22', '23', '24', '25', '26', '27', '28', '29', '30',
  '31', '32', '33', '34', '35', '36', '37', '38', '39', '40',
  '41', '42', '43', '44', '45', '46', '47', '48', '49', '50',
  '51', '52', '53', '54', '55', '56', '57', '58', '59', '60',
  '61', '62', '63', '64', '65', '66', '67', '68', '69', '70',
  '0+', '1+', '2+', '3+', '4+', '5+', '6+', '7+', '8+', '9+', '10+',
  '11+', '12+', '13+', '14+', '15+', '16+', '17+', '18+', '19+', '20+',
  '21+', '22+', '23+', '24+', '25+', '26+', '27+', '28+', '29+', '30+',
  '31+', '32+', '33+', '34+', '35+', '36+', '37+', '38+', '39+', '40+',
  '41+', '42+', '43+', '44+', '45+', '46+', '47+', '48+', '49+', '50+',
  '51+', '52+', '53+', '54+', '55+', '56+', '57+', '58+', '59+', '60+',
  '61+', '62+', '63+', '64+', '65+', '66+', '67+', '68+', '69+', '70+',
  '0-', '1-', '2-', '3-', '4-', '5-', '6-', '7-', '8-', '9-', '10-',
  '11-', '12-', '13-', '14-', '15-', '16-', '17-', '18-', '19-', '20-',
  '21-', '22-', '23-', '24-', '25-', '26-', '27-', '28-', '29-', '30-',
  '31-', '32-', '33-', '34-', '35-', '36-', '37-', '38-', '39-', '40-',
  '41-', '42-', '43-', '44-', '45-', '46-', '47-', '48-', '49-', '50-',
  '51-', '52-', '53-', '54-', '55-', '56-', '57-', '58-', '59-', '60-',
  '61-', '62-', '63-', '64-', '65-', '66-', '67-', '68-', '69-', '70-'
);

DROP TYPE IF EXISTS enum_bird_sex;
CREATE TYPE enum_bird_sex AS ENUM (
  'f', 'm', 'mu', 'fu', 'u'
);

DROP TYPE IF EXISTS enum_supported_prefix_numbers;
CREATE TYPE enum_supported_prefix_numbers AS ENUM (
  'aa', 'ae', 'ax', 'ap', 'a', 'b', 'bp', 'c', 'cp', 'cx', 'd', 'dp',
  'y', 'yp', 'e', 'h', 't', 'k', 's', 'sn', 'l', 'ln', 'lnc', 'v', 'w',
  'm', 'o', 'r', 'x', 'z', 'j', 'p', 'pa', 'ka', 'rc', 'ra', 'rh', 'web',
  'pit', '13', '19', '27', '12', '17', '23', '9', '15', '29', 'xbat', 'abat'
);

DROP TYPE IF EXISTS enum_upload_status;
CREATE TYPE enum_upload_status AS ENUM (
  'PENDING_RESULT', 
  'CRITICAL_FILE_FORMAT',
  'PASS_FILE_FORMAT',
  'WARNINGS',
  'CRITICALS',
  'WARNINGS_AND_CRITICALS',
  'PASS',
  'REQUEST_FOR_APPROVAL',
  'ADMIN_REJECTED',
  'ADMIN_APPROVED',
  'PUSHED_TO_DATABASE',
  'PROCESS_ERROR',
  'DEFUNCT'
);

DROP TYPE IF EXISTS enum_status_detail;
CREATE TYPE enum_status_detail AS ENUM (
  '01. Caught by banding operator in net or trap',
  '02. Roosting at site away from breeding area',
  '03. Seen feeding in natural habitat',
  '04. Seen feeding on supplementary food or at bird feeder',
  '05. Seen in natural habitat',
  '10. Shot (deliberate)',
  '11. Shot (for control operations)',
  '12. Found shot',
  '13. On road (car killed)',
  '14. On railway (train killed)',
  '15. On airport (plane killed)',
  '16. Killed by flying into immobile unnatural object',
  '17. Killed during recapture',
  '18. Poisoned',
  '19. Electrocuted',
  '20. Died shortly after release',
  '30. killed by cat',
  '31. killed by dog',
  '32. killed by mammal',
  '33. killed by avian predator',
  '34. killed by another bird',
  '35. killed by fish or reptile',
  '36. killed by unknown animal',
  '37. Caught in animal trap',
  '38. starvation',
  '40. Chick in nest',
  '49. At breeding colony',
  '50. Breeding',
  '51. Not breeding', 
  '52. Roosting on breeding locality outside breeding season',
  '53. On empty nest',
  '54. With mate on nesting territory',
  '55. With egg',
  '56. With more than one egg',
  '57. With chick',
  '58. With more than one chick',
  '59. Not breeding but with mate',
  '60. Died as chick on colony',
  '61. Died as Juvenile on colony',
  '62. Died as Adult on colony',
  '63. Died as Breeding adult with Egg',
  '64. Died as Breeding adult with Eggs',
  '65. Died as Breeding adult with Chick',
  '66. Died as breeding adult with Chicks',
  '79. Found on beach',
  '80. Found - no further details or circumstances',
  '81. cause unknown',
  '82. Injured - cause unknown',
  '83. Exhausted or ill',
  '84. Oiled',
  '85. Caught in natural hazard',
  '86. Caught in fishing net',
  '87. Caught in fishing line or hook',
  '88. Recovered by any other means on ship at sea',
  '89. Killed by weather',
  '91. Caught in net - inshore',
  '92. Caught in net - pelagic',
  '93. Caught in nest - no further details',
  '94. Caught on hook - Tuna longline',
  '95. Caught on hook - bottom line',
  '96. Caught on hook - inshore longline',
  '97. Caught on hook - handline or by angler',
  '98. Caught on hook - no further details'
);


DROP TYPE IF EXISTS enum_db_log_action;
CREATE TYPE enum_db_log_action AS ENUM (
  'DELETE', 
  'INSERT',
  'UPDATE'
);

/*  
 USERS
*/

/*
These users presume that Aurora is configured for IAM authentication. If that's not the case,
you'll need one DB user per actual user instead.

To use these roles, your IAM User or Role must have the following policy attached:

{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Action": [
             "rds-db:connect"
         ],
         "Resource": [
             "arn:aws:rds-db:us-east-2:1234567890:dbuser:cluster-ABCDEFGHIJKL01234/birdbanding_readonly"
         ]
      }
   ]
}        

In the case of lambda functions, this policy must be attached to the Lambda execution role.

*/

-- Read-Only User
CREATE USER birdbanding_readonly WITH LOGIN; 
GRANT rds_iam TO birdbanding_readonly;
GRANT CONNECT ON DATABASE birdbanding TO birdbanding_readonly;
GRANT USAGE ON SCHEMA public TO birdbanding_readonly;
GRANT USAGE ON SCHEMA aws_s3 TO birdbanding_readonly;
GRANT USAGE ON SCHEMA tiger TO birdbanding_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO birdbanding_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA tiger TO birdbanding_readonly;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA aws_s3 TO birdbanding_readonly;

-- read-Write User
CREATE USER birdbanding_readwrite WITH LOGIN; 
GRANT rds_iam TO birdbanding_readwrite;
GRANT CONNECT ON DATABASE birdbanding TO birdbanding_readwrite;
GRANT USAGE ON SCHEMA public TO birdbanding_readwrite;
GRANT USAGE ON SCHEMA aws_s3 TO birdbanding_readwrite;
GRANT USAGE ON SCHEMA tiger TO birdbanding_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO birdbanding_readwrite;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA tiger TO birdbanding_readwrite;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA aws_s3 TO birdbanding_readwrite;
