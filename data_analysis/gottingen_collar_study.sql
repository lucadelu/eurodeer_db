-- The queries below are used to extract information about collar performances shared with the project
-- of University of Göttingen, Germany

-- Bounding box and countries of study areas [question 1]
SELECT 
  study_areas_id, study_name, name, st_extent(geom_mcp_individuals)
FROM 
  main.study_areas, env_data.world_countries_simplified
WHERE 
  st_intersects(geom_mcp_individuals, world_countries_simplified.geom)
group by 
  study_areas_id, study_name, name
order by 
  study_areas_id;
  
-- Land cover classes distribution for each study area (in percentage, from Corine Land Cover 2006) [question 5]
WITH studyareas_landcover AS
    (
    SELECT 
      study_areas_id,
      (stats).value AS lc_id, 
      (stats).count AS num_pixels
    FROM (
      SELECT 
        study_areas_id, 
        ST_ValueCount(ST_Union(ST_Clip(rast ,ST_Transform(geom_mcp_individuals,3035))))  stats
      FROM
        main.study_areas,
        env_data.corine_land_cover_2006
      WHERE
        ST_Intersects (rast, ST_Transform(geom_mcp_individuals,3035))
      GROUP BY 
        study_areas_id) a
    )
SELECT
  study_areas_id,
  clc_l3_code,
  label3,
  ((num_pixels * 1.0 / (sum(num_pixels) over (PARTITION BY study_areas_id)))*100)::numeric(6,3) AS percentage
FROM 
  studyareas_landcover,
  env_data.corine_land_cover_legend
WHERE
  grid_code = lc_id
ORDER BY
  study_areas_id, clc_l3_code;
  
-- Start and end of monitoring per project [question 6]
SELECT 
  animals.study_areas_id, 
  MIN(gps_sensors_animals.start_time)::DATE start_monitoring, 
  max(gps_sensors_animals.end_time)::DATE end_monitoring
FROM 
  main.gps_sensors_animals, 
  main.animals
WHERE 
  animals.animals_id = gps_sensors_animals.animals_id AND 
  end_time is not null
GROUP BY 
  animals.study_areas_id
  order by 
  animals.study_areas_id;


-- Number of individual per area/sex/age (age at first capture) [question 7]
SELECT 
  study_areas_id, 'Capreolus capreolus', sex, age_class_description, count(*) 
FROM 
	(SELECT distinct
	  animals.study_areas_id, 
	  gps_sensors_animals.animals_id, 
	  animals.sex, 
	  lu_age_class.age_class_description
	FROM 
	  main.gps_sensors_animals, 
	  main.animals, 
	  lu_tables.lu_age_class
	WHERE 
	  animals.animals_id = gps_sensors_animals.animals_id AND
	  lu_age_class.age_class_code = animals.age_class_code_capture AND
	  gps_data) a
GROUP BY
  study_areas_id, sex, age_class_description
ORDER BY
  study_areas_id, sex, age_class_description;
  
-- Number of collars per area/brand/year [question 8]
SELECT 
  animals.study_areas_id,
  gps_sensors.vendor, 
  gps_sensors.model, 
  extract(year from gps_sensors_animals.start_time) yearx, 
  count(gps_sensors_animals.gps_sensors_id) 
FROM 
  main.gps_sensors, 
  main.gps_sensors_animals, 
  main.animals
WHERE 
  gps_sensors_animals_id IN 
  (SELECT gps_sensors_animals_id FROM(
	SELECT  gps_sensors_animals_id, rank() over(partition by gps_sensors_id ORDER BY start_time)  rankx
	  FROM main.gps_sensors_animals) a
  WHERE rankx = 1) AND
  gps_sensors.gps_sensors_id = gps_sensors_animals.gps_sensors_id AND
  gps_sensors_animals.animals_id = animals.animals_id
GROUP BY 
  animals.study_areas_id,
  gps_sensors.vendor, 
  gps_sensors.model, 
  extract(year from gps_sensors_animals.start_time)
ORDER BY 
  animals.study_areas_id,
  gps_sensors.vendor, 
  gps_sensors.model,
  extract(year from gps_sensors_animals.start_time);

-- Count how many collars per study areas grouped by maximum delay in seconds (from the supposed acquisition) [question 10]
WITH 

diff_time AS 
(SELECT 
  gps_sensors_id, 
  max(extract( epoch from acquisition_time -  tools.snap_timestamp(acquisition_time, 300)))::integer AS diff
FROM 
  main.gps_data_animals
where 
  gps_validity_code in (0,1)
group by 
  gps_sensors_id),
  
sensors_area AS
(SELECT 
  gps_sensors.gps_sensors_id, 
  animals.study_areas_id
FROM 
  main.gps_sensors, 
  main.gps_sensors_animals, 
  main.animals
WHERE 
  gps_sensors.gps_sensors_id = gps_sensors_animals.gps_sensors_id AND
  animals.animals_id = gps_sensors_animals.animals_id
GROUP BY
  gps_sensors.gps_sensors_id, 
  animals.study_areas_id)
   
SELECT
  study_areas_id,
  sum(CASE WHEN classx = 1 THEN 1 ELSE 0 END) AS less60,
  sum(CASE WHEN classx = 2 THEN 1 ELSE 0 END) AS less90,
  sum(CASE WHEN classx = 3 THEN 1 ELSE 0 END) AS less180,
  sum(CASE WHEN classx = 4 THEN 1 ELSE 0 END) AS less300
FROM
  sensors_area,
  (SELECT 
    gps_sensors_id, 
    CASE
    WHEN diff <= 60 then 1
    WHEN diff <= 90 THEN 2
    WHEN diff <= 180 THEN 3
    WHEN diff <= 300 THEN 4 END classx
  FROM 
    diff_time
  ) a
WHERE
  a.gps_sensors_id = sensors_area.gps_sensors_id
GROUP BY 
  study_areas_id;  

-- End of deployment [question 13]
SELECT 
  study_areas_id,
  lu_end_deployment.end_deployment_description, 
  count(gps_sensors_animals.gps_sensors_id) number_sensors
FROM 
  main.gps_sensors_animals, 
  lu_tables.lu_end_deployment,
  main.animals
WHERE 
  gps_sensors_animals.end_deployment_code = lu_end_deployment.end_deployment_code AND
  gps_sensors_animals.animals_id = animals.animals_id
GROUP BY
  study_areas_id,
  lu_end_deployment.end_deployment_description
ORDER BY 
  study_areas_id,
  lu_end_deployment.end_deployment_description;
  
-- Success rate [questions 15-16-17]
SELECT 
  animals.study_areas_id, 
  count(gps_data_animals.gps_validity_code) expected,
  sum(CASE WHEN gps_validity_code = 1 THEN 1 ELSE 0 END) successful,
  sum(CASE WHEN gps_validity_code = 0 THEN 1 ELSE 0 END) unsuccesful,
  sum(CASE WHEN gps_validity_code > 1 THEN 1 ELSE 0 END) wrong_data
FROM 
  main.animals, 
  main.gps_data_animals
WHERE 
  animals.animals_id = gps_data_animals.animals_id AND
  gps_validity_code != 14
GROUP BY   
  study_areas_id
ORDER BY
  study_areas_id;

-- Number of deployments per study area [extra question]
SELECT 
  study_areas_id, 
  count(*) num_deployments, 
  min(start_time::date) first_start, 
  max(end_time::date) last_end
FROM 
  main.gps_sensors_animals,
  main.animals
WHERE
  animals.animals_id = gps_sensors_animals.animals_id
GROUP BY 
  study_areas_id
ORDER BY 
  study_areas_id;
