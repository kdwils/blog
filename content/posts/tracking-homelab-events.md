+++
author = "Kyle Wilson"
title = "Tracking Homelab Events Featuring DuckDB"
date = "2026-01-26"
description = "How I started tracking events in my cluster backed by DuckDB"
summary = "I created a simple CRUD go application to feed events into DuckDB for my homelab"
tags = [
    "Self Host",
    "Kubernetes",
    "DuckDB"
]
+++

## Why?

I've had an interest in collecting analytics lately with regard to my homelab. Specifically, I was interested in traffic to the various self-hosted applications I deploy, but I also wanted something flexible enough for the one-off stats in the future that I think might be cool.

To do that, I needed the backing storage to be flexible enough to handle various payloads. Solutions like Clickhouse exist, and for the production world, they are obviously the better choice. But for a self-hoster, it's a lot of footprint for simple analytics. Once a separate database deployment is required I start to lose interest.

My main requirement is that the backing storage must be as self-hoster friendly as SQLite without the pain of figuring out how to query json shoved in a column. 

While SQLite is the obvious choice for embedded databases, DuckDB offered a compelling advantage: JSON support with stupidly simple querying. This made it the perfect solution for flexible event storage.

## Getting events to the database

I put together a simple go service with a few ideas in mind:
* Schema should be rigid enough to work with any event
* The service needed a way to accept payloads via webhook without specifying details in the request body
* Querying for data should be stupidly simple

You can view the [sourcecode](https://github.com/kdwils/events) on github

### Schema

Before we can write any data, the schema needs to be solidified. Because the payload will be dynamic, we need to take advantage of the JSON column type that DuckDB supports. The schema is intentionally simple: a few metadata columns to categorize events, and a flexible JSON column to store the actual event data without needing to define a rigid structure upfront. 

```sql
CREATE SEQUENCE IF NOT EXISTS events_id_seq START 1;

CREATE TABLE IF NOT EXISTS events (
    id BIGINT PRIMARY KEY DEFAULT nextval('events_id_seq'),
    event_type VARCHAR NOT NULL,
    source VARCHAR NOT NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    payload JSON NOT NULL
);
```

### Ingestion
Next, we need a design for a webhook that works for any integration. For most event providers, you probably can't modify the payload sent, but you *must* supply a url for it to hit (duh).

The easiest solution here was to build out some of the metadata in the API. With `{event_source}` and `{event_type}` being dynamic, webhooks could be configured for many sources supporting any type of event. The request body can also contain additional metadata if desired.

```shell
curl -X POST 'http://localhost:8080/api/v1/events/{event_source}/{event_type}' \
  --header 'Accept: */*' \
  --header 'Content-Type: application/json' \
  --data '{ "family": "anatidae", "species": [ "duck", "goose", "swan", null ], "age": 19 }'
```

In my Radarr instance, I configured a notification for when a movie is added by adding: `https://events.int.kyledev.co/api/v1/events/radarr/movie_added`

Which results in events like
```json
{
  "id": 993,
  "event_type": "movie_added",
  "source": "radarr",
  "received_at": "2026-01-27T05:01:44.233392Z",
  "payload": {
    "some": "data"
  }
}
```

I also wanted a single point of integration for tracking traffic to my self-hosted applications. Last year, I made the cutover from `ingress-nginx` to `envoy-gateway` with great success.

Since `envoy-gateway` supports [wasm extensions](https://gateway.envoyproxy.io/docs/tasks/extensibility/wasm/), and I had never used wasm before, this felt like a great learning opportunity.

I made a [simple extension](https://github.com/kdwils/envoy-wasm-traffic-plugin) in Rust that essentially fires off an event for each request that is routed through my gateway. By default, it will attempt to parse out the real IP of the client, and the host of the request. It can also be configured to supply additional headers if desired. Then, I deployed envoy-gateway with the extension for testing. You can see my configuration in my [homelab](https://github.com/kdwils/homelab/tree/main/infra/envoy-gateway) repository.

Finally, some real data to play with, even if it is mostly traffic from bots.

My final configuration for the extension looked like
```yaml
config:
  webhook_cluster: "webhook_cluster"
  webhook_authority: "events.int.kyledev.co"
  webhook_path: "/api/v1/events/envoy-gateway/http_request"
  trusted_proxies:
    - "10.42.0.0/16" # cidr range for pod vips internally in my cluster
```

Which produced events for http requests like
```json
{
  "id": 1002,
  "event_type": "http_request",
  "source": "envoy-gateway",
  "received_at": "2026-01-27T05:04:44.070494Z",
  "payload": {
    "authority": "blog.kyledev.co",
    "client_ip": "192.168.0.1",
    "headers": {}
  }
}
```

### Retrieval
Beyond generic CRUD operations, I wanted a way to perform adhoc queries in a way that was super simple. I also had a desire to build a CLI command that worked for remote instances as well. Essentially, we needed an API endpoint that was a wrapper around reads. It simply needs to take query input, and generically serialize it to columns and rows.

We ended up with the following:
```go
type QueryResult struct {
	Columns []string
	Rows    [][]any
}

func (d *DB) Adhoc(ctx context.Context, query string) (*QueryResult, error) {
	rows, err := d.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	columns, err := rows.Columns()
	if err != nil {
		return nil, err
	}

	var results [][]any
	for rows.Next() {
		values := make([]any, len(columns))
		valuePtrs := make([]any, len(columns))
		for i := range values {
			valuePtrs[i] = &values[i]
		}

		if err := rows.Scan(valuePtrs...); err != nil {
			return nil, err
		}

		results = append(results, values)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &QueryResult{
		Columns: columns,
		Rows:    results,
	}, nil
}
```

This allowed the API to return flexible responses that can be transformed to tabular content.

### Example Queries

We can now retrieve our *very* real and not bot-like traffic through adhoc queries. I've added a simple CLI that makes a HTTP request with the query and displays the data. This endpoint is not secure whatsoever.

The art of shoving a SQL query into a CLI command is crude, but it is functional, and there is plenty of room to improve on the UX. 

I've formatted the queries for the sake of your eyes.

#### Requests made to this blog
```sql
SELECT json_extract_string(payload, '$.authority') AS HOST,
       COUNT(*) AS request_count
FROM EVENTS
WHERE event_type = 'http_request'
  AND json_extract_string(payload, '$.authority') = 'blog.kyledev.co'
GROUP BY HOST
ORDER BY request_count DESC
```

```shell
+-----------------+---------------+
| host            | request_count |
+-----------------+---------------+
| blog.kyledev.co | 6.000000      |
+-----------------+---------------+

(1 rows)
```

#### Total requests made by an IP address including how many unique hosts hit
```sql
SELECT json_extract_string(payload, '$.client_ip') AS ip_address,
       COUNT(DISTINCT json_extract_string(payload, '$.authority')) AS unique_hosts,
       COUNT(*) AS total_requests
FROM EVENTS
WHERE event_type = 'http_request'
ORDER BY unique_hosts DESC,
         total_requests DESC
LIMIT 5
```

```shell
+----------------+--------------+----------------+
| ip_address     | unique_hosts | total_requests |
+----------------+--------------+----------------+
| 10.42.2.0      | 7.000000     | 849.000000     |
| 74.98.232.127  | 3.000000     | 161.000000     |
| 172.70.35.19   | 1.000000     | 136.000000     |
| 172.71.191.113 | 1.000000     | 13.000000      |
| 15.204.162.26  | 1.000000     | 4.000000       |
+----------------+--------------+----------------+

(5 rows)
```

#### Request Velocity
```sql
SELECT json_extract_string(payload, '$.client_ip') AS ip,
       date_trunc('minute', received_at) AS MINUTE,
       COUNT(*) AS requests
FROM EVENTS
WHERE event_type = 'http_request'
GROUP BY ip,
         MINUTE
HAVING COUNT(*) > 10
ORDER BY requests DESC
```
```shell
+----------------+----------------------+------------+
| ip             | minute               | requests   |
+----------------+----------------------+------------+
| 172.70.35.19   | 2026-01-27T03:34:00Z | 136.000000 |
| 10.42.2.0      | 2026-01-27T03:26:00Z | 87.000000  |
| 10.42.2.0      | 2026-01-27T05:00:00Z | 69.000000  |
| 10.42.2.0      | 2026-01-27T03:35:00Z | 69.000000  |
| 10.42.2.0      | 2026-01-27T03:33:00Z | 54.000000  |
| 74.98.232.127  | 2026-01-27T04:37:00Z | 53.000000  |
| 10.42.2.0      | 2026-01-27T03:34:00Z | 51.000000  |
| 10.42.2.0      | 2026-01-27T03:36:00Z | 50.000000  |
| 10.42.2.0      | 2026-01-27T03:27:00Z | 37.000000  |
| 10.42.2.0      | 2026-01-27T03:32:00Z | 33.000000  |
| 10.42.2.0      | 2026-01-27T03:38:00Z | 29.000000  |
| 10.42.2.0      | 2026-01-27T03:37:00Z | 27.000000  |
| 10.42.2.0      | 2026-01-27T03:31:00Z | 26.000000  |
| 10.42.2.0      | 2026-01-27T03:30:00Z | 22.000000  |
| 10.42.2.0      | 2026-01-27T03:29:00Z | 20.000000  |
| 10.42.2.0      | 2026-01-27T03:39:00Z | 17.000000  |
| 74.98.232.127  | 2026-01-27T02:30:00Z | 16.000000  |
| 74.98.232.127  | 2026-01-27T02:31:00Z | 14.000000  |
| 74.98.232.127  | 2026-01-27T04:44:00Z | 14.000000  |
| 172.71.191.113 | 2026-01-27T03:48:00Z | 13.000000  |
| 74.98.232.127  | 2026-01-27T02:32:00Z | 13.000000  |
| 74.98.232.127  | 2026-01-27T02:33:00Z | 11.000000  |
+----------------+----------------------+------------+

(22 rows)
```


## What's Next
A simple dashboard would go a long way for viewing metrics

[duckui.com](https://duckui.com/) exists, and seems like the most complete option available. This could live as a sidecar deployed alongside my service.

An [extension](https://duckdb.org/docs/stable/core_extensions/ui) exists, but seems to be tailored for local use

There is [support](https://duckdb.org/docs/stable/guides/network_cloud_storage/duckdb_over_https_or_s3) for connecting remotely to a database that is exposed

The events service could also support a dashboard for simple read operations, but I would rather not reinvent the wheel here. As of the writing of this post, I am leaning towards a solution with `duckui.com`

Overall, DuckDB was a fantastic choice for a self-hosted option for storing simple events and metrics. I'm looking forward to adding more events in the future.