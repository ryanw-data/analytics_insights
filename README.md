# Insight into your Tableau applications and engagement
With this Tableau companion application, Tableau Creators can learn how their applications are being used, optimise their content, and close any shortcomings or gaps in their analytical offering.


## Pre-Reqs

1. You will need access to your [Tableau Server metadata](https://help.tableau.com/current/server/en-us/perf_collect_server_repo.htm "Tableau Documentation"), also known as the workgroup database
2. You will need a Tableau Creator licence (and Tableau Desktop client prefered)


## Getting Started

1. Clone this repository to a local directory
2. 


## Architecture

### Data Model

The primary source for this application is the Tableau Server's metadata AKA the workgroup database. You can read more about this datasource [here](https://help.tableau.com/current/server/en-us/data_dictionary.htm "Tableau Documentation").

Each box in the diagram below is built using custom SQL against the workgroup database, the relationships between each table is shown on the diagram

![Data Architecture](https://github.com/ryanw-data/analytics_insights/blob/main/data_structure.png?raw=true)

| Table Name | Description | Code |
| ------ | ------ | ------ |
| EVENTS | The core fact table. A row for every **_engagement action_** taken by a user on the server | [EVENTS.SQL](SQL/EVENTS.sql) |
| CONTENT | A dimention table that links workbooks and datasources to their highest parent folder (max. 5 nested folders) | [CONTENT.SQL](SQL/CONTENT.sql) |
| USERS_DAILY | A daily history for each user account showing what users are licenced on a given day. Only licenced users are included | [USERS_DAILY.SQL](SQL/USERS_DAILY.sql) |
| USER_GROUPS_DAILY | A daily history for user group membership showing what groups a user had on a given date | [USER_GROUPS_DAILY.SQL](SQL/USER_GROUPS_DAILY.sql) |

### Application Architecture


