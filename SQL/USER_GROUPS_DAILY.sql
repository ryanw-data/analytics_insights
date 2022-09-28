WITH GROUP_MEMBERSHIP_CHANGES AS (
    --Returns all "user licence update" events types from the commercial site
    SELECT 
    su.ID SYSTEM_USER_ID,
    su.email user_email, 
    u.USER_ID,
    CASE WHEN he.HISTORICAL_EVENT_TYPE_ID = 42 THEN 'ADDED' ELSE 'REMOVED' END UPDATE_TYPE, --converting ID to text
    he.CREATED_AT CHANGE_TIME,
    DATE_TRUNC('day', he.CREATED_AT)::DATE CHANGE_DATE, --removing timestamp from CHANGE_TIME
    hg.NAME GROUP_NAME,
    hg.GROUP_ID GROUP_ID,
    ROW_NUMBER() OVER(PARTITION BY su.email, hg.NAME ORDER BY he.CREATED_AT) rn --order of events per user per group
    FROM HISTORICAL_EVENTS he
    JOIN HIST_USERS u ON u.ID = he.hist_target_user_id
    JOIN SYSTEM_USERS su ON su.ID = u.system_user_id
    JOIN HIST_GROUPS hg ON hg.ID = he.HIST_GROUP_ID
    WHERE he.HISTORICAL_EVENT_TYPE_ID IN (42,43) --only add or remove from group events
    AND he.HIST_TARGET_SITE_ID = 5 --only commercial site
),
EVENT_START_DATE AS (
    --Returns the first event time and date from events table for use in later CTEs
    SELECT 
    MIN(CREATED_AT) MIN_CHANGE_TIME,
    DATE_TRUNC('day', MIN(CREATED_AT))::DATE MIN_CHANGE_DATE
    FROM HISTORICAL_EVENTS
),
START_EVENTS AS (
    --If the first event is removed then creates a fake added row to act as the starting point
    SELECT 
    gmc.SYSTEM_USER_ID,
    gmc.USER_EMAIL,
    gmc.USER_ID,
    'ADDED' UPDATE_TYPE, --Assume that must have been in the group "added" if first event is removed
    esd.MIN_CHANGE_TIME CHANGE_TIME,
    esd.MIN_CHANGE_DATE CHANGE_DATE,
    gmc.GROUP_NAME,
    gmc.GROUP_ID
    FROM GROUP_MEMBERSHIP_CHANGES gmc
    CROSS JOIN EVENT_START_DATE esd
    WHERE gmc.rn = 1 --returns only first row per user per group
    AND gmc.UPDATE_TYPE = 'REMOVED' --only rows where the user was removed from a group
),
GROUP_MEMBERSHIP AS (
    --Returns currently group memberships in the commercial site to act as the default list if no events exist
    SELECT 
    su.ID SYSTEM_USER_ID,
    su.EMAIL USER_EMAIL,
    u.ID USER_ID,
    'ADDED' UPDATE_TYPE, --Only active memberships exist in tables, so only one possible status
    esd.MIN_CHANGE_TIME CHANGE_TIME,
    esd.MIN_CHANGE_DATE CHANGE_DATE,
    g.NAME GROUP_NAME,
    g.ID GROUP_ID
    FROM GROUP_USERS gu
    JOIN USERS u ON u.ID = gu.USER_ID
    JOIN SYSTEM_USERS su ON su.ID = u.SYSTEM_USER_ID
    JOIN GROUPS g ON g.ID = gu.GROUP_ID 
    CROSS JOIN EVENT_START_DATE esd
    WHERE gu.SITE_ID = 5 --commercial site only
    AND NOT EXISTS (SELECT * FROM GROUP_MEMBERSHIP_CHANGES gmc WHERE gmc.USER_EMAIL = su.EMAIL AND gmc.GROUP_NAME = g.NAME) --only if there is no rows in event CTE
),
UNIONED_DATASETS AS (
    --A combined dataset with all events ready to create a daily timeseries
    SELECT res_2.*,
    MIN(res_2.CHANGE_DATE) OVER(PARTITION BY res_2.USER_EMAIL, res_2.GROUP_NAME ORDER BY res_2.CHANGE_DATE) FIRST_EVENT_DATE --the first event for the user in the group, acts as start of timeseries
    FROM (
        SELECT res_1.*,
        ROW_NUMBER() OVER(PARTITION BY res_1.USER_EMAIL, res_1.GROUP_NAME, res_1.CHANGE_DATE ORDER BY res_1.CHANGE_TIME) rn --ranks events per user per group per day
        FROM (
            --combines the event CTEs into a single stream per user per group
            SELECT SYSTEM_USER_ID, USER_EMAIL, USER_ID, UPDATE_TYPE, CHANGE_TIME, CHANGE_DATE, GROUP_NAME, GROUP_ID
            FROM GROUP_MEMBERSHIP_CHANGES
            UNION ALL
            SELECT SYSTEM_USER_ID, USER_EMAIL, USER_ID, UPDATE_TYPE, CHANGE_TIME, CHANGE_DATE, GROUP_NAME, GROUP_ID
            FROM START_EVENTS
            UNION ALL
            SELECT SYSTEM_USER_ID, USER_EMAIL, USER_ID, UPDATE_TYPE, CHANGE_TIME, CHANGE_DATE, GROUP_NAME, GROUP_ID
            FROM GROUP_MEMBERSHIP
        ) res_1
    ) res_2
    WHERE rn = 1 --only return the last row per user per group per day, de-duping events in a single day to just the most recent event
),
DATE_RANGE AS (
    --cross join to create a new grain, user per day per group
    SELECT *
    FROM (
        SELECT date_trunc('day', dd)::DATE DATES
        FROM generate_series ('now'::timestamp - '10 month'::interval, 'now'::timestamp, '1 day'::interval) dd
    ) res_1
    CROSS JOIN (SELECT DISTINCT USER_EMAIL, GROUP_NAME, GROUP_ID, SYSTEM_USER_ID, FIRST_EVENT_DATE, USER_ID FROM UNIONED_DATASETS) x
    WHERE x.FIRST_EVENT_DATE <= res_1.DATES --only keep rows where the user and group had a relationship
)
SELECT *
FROM (
    SELECT 
    VIEW_DATE,
    SYSTEM_USER_ID,
    USER_EMAIL,
    USER_ID,
    GROUP_NAME,
    GROUP_ID,
    FIRST_VALUE(UPDATE_TYPE) OVER(PARTITION BY USER_EMAIL, PARTITION_WINDOW ORDER BY VIEW_DATE) UPDATE_TYPE --backfill value
    FROM (
        --Subquery is to add all required columns into a single series per user per day per group and adds columns needed for backfill
        SELECT 
        dr.DATES VIEW_DATE,
        dr.SYSTEM_USER_ID,
        dr.USER_EMAIL,
        dr.USER_ID,
        dr.GROUP_NAME,
        dr.GROUP_ID,
        ud.UPDATE_TYPE,
        SUM(CASE WHEN ud.UPDATE_TYPE IS NULL THEN 0 ELSE 1 END) OVER(PARTITION BY dr.USER_EMAIL, dr.GROUP_NAME ORDER BY dr.DATES) PARTITION_WINDOW --incremental counter to act as a marker for backfill in outer query
        FROM DATE_RANGE dr
        LEFT JOIN UNIONED_DATASETS ud ON ud.USER_EMAIL = dr.USER_EMAIL AND ud.GROUP_NAME = dr.GROUP_NAME AND ud.CHANGE_DATE = dr.DATES
    ) res_1
    --WHERE GROUP_NAME != 'All Users' --removes the generic all users group
) res_2
WHERE UPDATE_TYPE != 'REMOVED' --only keep rows if they represent an active membership
ORDER BY USER_EMAIL, GROUP_NAME, VIEW_DATE