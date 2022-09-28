SELECT 
g.ID GROUP_ID,
g.NAME GROUP_NAME,
LEFT(g.NAME, position(' - ' in g.NAME) - 1) group_domain
FROM GROUPS g
WHERE position(' - ' in g.NAME)>0
AND SITE_ID = 5