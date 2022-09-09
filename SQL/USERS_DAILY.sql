WITH USER_UPDATES AS (
    --Returns all "user licence update" events types from the commercial site
    SELECT 
    CASE WHEN sr.ID IN (8) THEN 'Unlicenced' ELSE 'Licenced' END LICENCE_STATUS, --if not 8 unlicenced then must be licenced
    su.EMAIL USER_EMAIL,
    su.ID SYSTEM_USER_ID,
    he.CREATED_AT CHANGE_TIME,
    DATE_TRUNC('day',he.CREATED_AT)::DATE CHANGE_DATE, --removing the timestamp from CHANGE_TIME
    ROW_NUMBER() OVER(PARTITION BY su.EMAIL ORDER BY he.CREATED_AT) rn --order of events per user
    FROM HISTORICAL_EVENTS he
    JOIN HIST_USERS u ON u.ID = he.HIST_TARGET_USER_ID
    JOIN SYSTEM_USERS su ON su.ID = u.SYSTEM_USER_ID
    JOIN SITE_ROLES sr ON sr.ID = u.SITE_ROLE_ID
    WHERE he.HISTORICAL_EVENT_TYPE_ID = 18 --only "user licence update" event types
    AND he.HIST_TARGET_SITE_ID = 5 --only commercial type
),
EVENT_START_DATE AS (
    --Returns the first event time and date for use in later CTEs
    SELECT 
    MIN(CREATED_AT) MIN_CHANGE_TIME,
    DATE_TRUNC('day',MIN(CREATED_AT))::DATE MIN_CHANGE_DATE
    FROM HISTORICAL_EVENTS
),
START_EVENT AS (
    --If the first event is unlicenced then creates a fake licenced row to act as the starting point
    SELECT
    'Licenced' LICENCE_STATUS, --Assume that must have been licenced if first event is unlicenced
    USER_EMAIL,
    SYSTEM_USER_ID,
    esd.MIN_CHANGE_TIME CHANGE_TIME,
    esd.MIN_CHANGE_DATE CHANGE_DATE
    FROM USER_UPDATES
    CROSS JOIN EVENT_START_DATE esd
    WHERE rn = 1 --only return the first update event for each user
    AND LICENCE_STATUS = 'Unlicenced' --only return unlicenced events
),
LICENCED_USERS AS (
    --Returns currently licenced users in the commercial site to act as the default list if no events exist
    SELECT 
    'Licenced' LICENCE_STATUS, --unlicenced type removed in where clause, everything else is varient on licenced
    su.EMAIL USER_EMAIL,
    su.ID SYSTEM_USER_ID,
    esd.MIN_CHANGE_TIME CHANGE_TIME,
    esd.MIN_CHANGE_DATE CHANGE_DATE
    FROM USERS u
    JOIN SYSTEM_USERS su ON su.ID = u.SYSTEM_USER_ID
    CROSS JOIN EVENT_START_DATE esd
    WHERE u.SITE_ID = 5 --only commercial type
    AND u.SITE_ROLE_ID NOT IN (8) --removes "unlicenced" type
    AND su.ID NOT IN (SELECT SYSTEM_USER_ID FROM USER_UPDATES) --only return users that have had no update events
),
UNIONED_DATASET AS (
--Combines the three event CTEs into a single event stream and takes the latest event per day to create a grain of per user per day
SELECT *, MIN(res_2.CHANGE_DATE) OVER(PARTITION BY res_2.USER_EMAIL ORDER BY res_2.CHANGE_DATE) FIRST_EVENT_DATE
FROM (
    SELECT res_1.*,
    ROW_NUMBER() OVER(PARTITION BY res_1.USER_EMAIL, res_1.CHANGE_DATE ORDER BY res_1.CHANGE_TIME) rn --latest row per day per user
    FROM (
        SELECT LICENCE_STATUS, USER_EMAIL, SYSTEM_USER_ID, CHANGE_TIME, CHANGE_DATE
        FROM USER_UPDATES
        UNION ALL
        SELECT LICENCE_STATUS, USER_EMAIL, SYSTEM_USER_ID, CHANGE_TIME, CHANGE_DATE
        FROM START_EVENT 
        UNION ALL
        SELECT LICENCE_STATUS, USER_EMAIL, SYSTEM_USER_ID, CHANGE_TIME, CHANGE_DATE
        FROM LICENCED_USERS
    ) res_1
) res_2
WHERE rn = 1 --only return the latest row per user per day
AND USER_EMAIL IS NOT NULL --user must have an email
),
DATE_RANGE AS (
--Expands the event stream out to include a row per day per user even if an event did not happen
    SELECT *
    FROM (
        SELECT date_trunc('day', dd)::DATE DATES
        FROM generate_series ('2015-01-01'::timestamp, 'now'::timestamp, '1 day'::interval) dd --creates a generic date series
    ) res_1
    CROSS JOIN (SELECT DISTINCT USER_EMAIL, FIRST_EVENT_DATE, SYSTEM_USER_ID FROM UNIONED_DATASET) x --Explodes out the dataset to create the grain
    WHERE x.FIRST_EVENT_DATE <= res_1.DATES --only includes dates after the first event date
)
SELECT *
FROM (
--Final output that includes all rows with backfill included
    SELECT
    VIEW_DATE,
    FIRST_VALUE(LICENCE_STATUS) OVER(PARTITION BY USER_EMAIL, PARTITION_WINDOW ORDER BY VIEW_DATE) LICENCE_STATUS, --backfill value
    USER_EMAIL,
    SYSTEM_USER_ID,
    CASE WHEN rn_desc = 1 THEN 1 ELSE 0 END CURRENT_DATE_FLAG --if the row is the most recent for user then 1
    FROM (
        --Subquery is to add all required columns into a single series per user per day and adds columns needed for backfill
        SELECT 
        dr.DATES VIEW_DATE,
        ud.LICENCE_STATUS,
        dr.USER_EMAIL,
        dr.SYSTEM_USER_ID,
        SUM(CASE WHEN ud.FIRST_EVENT_DATE IS NULL THEN 0 ELSE 1 END) OVER(PARTITION BY dr.USER_EMAIL ORDER BY dr.DATES) PARTITION_WINDOW, --incremental counter to act as a marker for backfill in outer query
        ROW_NUMBER() OVER(PARTITION BY dr.USER_EMAIL ORDER BY dr.DATES DESC) rn_desc --row number to find latest row per user
        FROM DATE_RANGE dr
        LEFT JOIN UNIONED_DATASET ud ON dr.DATES = ud.CHANGE_DATE AND dr.USER_EMAIL = ud.USER_EMAIL
    ) res_1
) res_2
WHERE LICENCE_STATUS = 'Licenced'
ORDER BY USER_EMAIL, VIEW_DATE