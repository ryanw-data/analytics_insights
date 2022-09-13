WITH ALL_PROJECTS AS (
SELECT *
FROM PROJECTS_CONTENTS
WHERE SITE_ID = 5 --commercial site only
AND CONTENT_TYPE = 'project' --projects only
),
tier_1 AS (
    --returns all the top level projects you see on the landing screen of the commercial explore page
    SELECT 
    p.NAME t1_project_name,
    NULL t2_project_name,
    p.NAME PROJECT_NAME,
    p.ID PROJECT_ID,
    1 PROJECT_LEVEL
    FROM ALL_PROJECTS ap
    JOIN PROJECTS p ON p.ID = ap.CONTENT_ID
    WHERE ap.PROJECT_ID IS NULL --NO PARENT FOLDER
    --AND ap.CONTENT_ID = 41
),
tier_2 AS (
    SELECT 
    t1.t1_project_name,
    p.NAME t2_project_name,
    p.NAME PROJECT_NAME,
    p.ID PROJECT_ID,
    2 PROJECT_LEVEL
    FROM ALL_PROJECTS ap
    JOIN tier_1 t1 ON t1.PROJECT_ID = ap.CONTENT_ID
    JOIN ALL_PROJECTS ap1 ON ap1.PROJECT_ID = ap.CONTENT_ID
    JOIN PROJECTS p ON p.ID = ap1.CONTENT_ID
),
tier_3 AS (
    SELECT 
    t2.t1_project_name,
    t2.t2_project_name,
    p.NAME PROJECT_NAME,
    p.ID PROJECT_ID,
    3 PROJECT_LEVEL
    FROM ALL_PROJECTS ap
    JOIN tier_2 t2 ON t2.PROJECT_ID = ap.CONTENT_ID
    JOIN ALL_PROJECTS ap1 ON ap1.PROJECT_ID = ap.CONTENT_ID
    JOIN PROJECTS p ON p.ID = ap1.CONTENT_ID
),
tier_4 AS (
    SELECT 
    t3.t1_project_name,
    t3.t2_project_name,
    p.NAME PROJECT_NAME,
    p.ID PROJECT_ID,
    4 PROJECT_LEVEL
    FROM ALL_PROJECTS ap
    JOIN tier_3 t3 ON t3.PROJECT_ID = ap.CONTENT_ID
    JOIN ALL_PROJECTS ap1 ON ap1.PROJECT_ID = ap.CONTENT_ID
    JOIN PROJECTS p ON p.ID = ap1.CONTENT_ID
),
tier_5 AS (
    SELECT 
    t4.t1_project_name,
    t4.t2_project_name,
    p.NAME PROJECT_NAME,
    p.ID PROJECT_ID,
    5 PROJECT_LEVEL
    FROM ALL_PROJECTS ap
    JOIN tier_4 t4 ON t4.PROJECT_ID = ap.CONTENT_ID
    JOIN ALL_PROJECTS ap1 ON ap1.PROJECT_ID = ap.CONTENT_ID
    JOIN PROJECTS p ON p.ID = ap1.CONTENT_ID
)
SELECT *
FROM tier_1
UNION ALL
SELECT *
FROM tier_2
UNION ALL
SELECT *
FROM tier_3
UNION ALL
SELECT *
FROM tier_4
UNION ALL
SELECT *
FROM tier_5