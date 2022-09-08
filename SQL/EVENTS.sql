WITH EVENTS as (
    SELECT
    su.ID SYSTEM_USER_ID,
    su.EMAIL USER_EMAIL,
    het.name event_type, 
    he.created_at event_time,
    LAG(he.created_at) OVER(PARTITION BY su.EMAIL ORDER BY he.created_at) prev_event_time,
    LEAD(he.created_at) OVER(PARTITION BY su.EMAIL ORDER BY he.created_at) next_event_time,
    hs.name site_name,
    hp.name project_name,
    hw.name workbook_name,
    hv.name view_name,
    hd.name datasource_name
    FROM historical_events he
    JOIN historical_event_types het ON het.type_id = he.historical_event_type_id
    LEFT JOIN HIST_USERS hu ON hu.ID = he.hist_actor_user_id
    LEFT JOIN SYSTEM_USERS su ON su.ID = hu.SYSTEM_USER_ID
    LEFT JOIN hist_sites hs ON hs.id = he.hist_actor_site_id
    LEFT JOIN hist_projects hp ON hp.id = he.hist_project_id
    LEFT JOIN hist_workbooks hw ON hw.ID = he.hist_workbook_id
    LEFT JOIN hist_views hv ON hv.id = he.hist_view_id
    LEFT JOIN hist_datasources hd ON hd.id = he.hist_datasource_id
    WHERE (he.hist_target_site_id = 5 OR he.hist_target_site_id IS NULL) --commercial site or generic site-less events only
    AND het.action_type = 'Access'
    ORDER BY su.EMAIL, he.created_at
),
ENRICHED_EVENTS as (
    SELECT *,   
    COUNT(CASE WHEN event_type = 'Login' THEN 1 
               WHEN prev_event_time IS NULL THEN 1
               WHEN event_time - prev_event_time > INTERVAL '30 minute' THEN 1
               ELSE NULL END) OVER(PARTITION BY SYSTEM_USER_ID ORDER BY event_time) login_count
    FROM EVENTS
),
SESSION_DETAIL AS (
    SELECT *,
    CONCAT(CEIL(EXTRACT(epoch from FIRST_VALUE(event_time) OVER(PARTITION BY login_count, SYSTEM_USER_ID ORDER BY event_Time))), SYSTEM_USER_ID) session_id
    FROM ENRICHED_EVENTS
    ORDER BY SYSTEM_USER_ID, event_time
)
SELECT * 
FROM SESSION_DETAIL
ORDER BY SYSTEM_USER_ID, event_time