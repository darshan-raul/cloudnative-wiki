---
title: GCP Cloud SQL
description: Cloud SQL architecture — High Availability (HA) regional failover, Cloud SQL Auth Proxy, IAM database authentication, read replicas, and connection pooling.
tags:
  - gcp
  - databases
  - cloud-sql
  - postgres
  - mysql
  - security
---

# GCP Cloud SQL 🗄️

Google Cloud SQL is a fully managed relational database service supporting **PostgreSQL**, **MySQL**, and **SQL Server**. Cloud SQL automates provisioning, storage autoscaling, high availability replication, automated point-in-time recovery (PITR), and security patching.

---

## Architecture & Mental Model

### High Availability (HA) Regional Failover

Cloud SQL achieves high availability through synchronous block-level storage replication between two zones in the same region:

```
                    ┌─────────────────────────┐
                    │  Application / GKE Pod  │
                    └────────────┬────────────┘
                                 │ Connects to Static Virtual IP
                                 ▼
                     Cloud SQL Virtual IP Routing
                                 │
                 ┌───────────────┴───────────────┐
                 │ (Normal Operation)            │ (Failover Operation)
                 ▼                               ▼
     ┌───────────────────────┐       ┌───────────────────────┐
     │  Primary Instance     │       │  Standby Instance     │
     │     (Zone-a)          │       │     (Zone-b)          │
     └───────────┬───────────┘       └───────────┬───────────┘
                 │                               │
                 │   Synchronous Disk Mirroring  │
                 └───────────────►───────────────┘
                     Regional Persistent Disk
```

* **Zero Data Loss (RPO = 0):** Because storage is replicated synchronously at the block level before transactions commit, zero data is lost during an unexpected zone failure.
* **Automated Failover (RTO ~60–120s):** If the primary fails health checks, the virtual IP automatically redirects connections to the standby node.

---

## Core Concepts

### 1. Cloud SQL Auth Proxy

Connecting to databases across the public internet or private VPCs traditionally requires firewall IP whitelisting and manual SSL/TLS certificate distribution. **Cloud SQL Auth Proxy** solves this:
* Runs as a local sidecar container or background daemon alongside your application.
* Establishes a secure mTLS tunnel to Cloud SQL over port 3307.
* Authenticates using **Google Cloud IAM credentials** rather than network IP allowlists.
* Automatically handles certificate rotation every hour without connection drops.

### 2. IAM Database Authentication

Eliminates static, hard-coded database passwords in configuration files:
* Maps a Google Cloud Service Account directly to an internal PostgreSQL or MySQL user.
* Applications acquire an ephemeral 1-hour OAuth 2.0 access token from the metadata server and supply it as the database password during connection handshake.

### 3. Read Replicas & Cross-Region DR

* **Read Replicas:** Asynchronously replicated instances used to offload read-heavy analytics and BI queries.
* **Cross-Region Replicas:** Replicates data to a distant geographical region. In the event of a total regional disaster, the cross-region replica can be promoted to a standalone read/write primary.

### 4. Automated Storage Capacity Increases

Cloud SQL supports automated storage expansion:
* Automatically adds disk space in real time when free storage drops below 10%.
* **Crucial Architectural Constraint:** Disk storage can **only grow**; it can **never be shrunk**. If a query accidentally writes 5 TB of temporary table data, you will pay for 5 TB of disk permanently unless you export and recreate the instance.

---

## Production `gcloud` CLI Commands

### 1. Provisioning a Production PostgreSQL Instance with HA and Private IP

```bash
gcloud sql instances create prod-pg-cluster \
  --database-version=POSTGRES_16 \
  --tier=db-custom-4-16384 \
  --region=us-central1 \
  --availability-type=REGIONAL \
  --storage-type=SSD \
  --storage-size=100GB \
  --storage-auto-increase \
  --network=projects/my-prod-project/global/networks/prod-vpc \
  --no-assign-ip \
  --database-flags=cloudsql.iam_authentication=on,max_connections=300 \
  --backup-start-time=02:00 \
  --enable-point-in-time-recovery \
  --maintenance-window-day=SUN \
  --maintenance-window-hour=04
```

### 2. Creating an IAM-Authenticated Database User

```bash
# Add a service account as an authenticated DB user
gcloud sql users create payment-sa@my-prod-project.iam \
  --instance=prod-pg-cluster \
  --type=CLOUD_IAM_SERVICE_ACCOUNT
```

### 3. Running Cloud SQL Auth Proxy in Kubernetes (Sidecar)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
spec:
  template:
    spec:
      containers:
        # Main application container
        - name: app
          image: gcr.io/my-prod-project/api:v1.0
          env:
            - name: DB_HOST
              value: "127.0.0.1" # Connects to local proxy sidecar
            - name: DB_PORT
              value: "5432"

        # Cloud SQL Auth Proxy Sidecar
        - name: cloud-sql-proxy
          image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.0
          args:
            - "--structured-logs"
            - "--port=5432"
            - "my-prod-project:us-central1:prod-pg-cluster"
          securityContext:
            runAsNonRoot: true
```

---

## Quotas & Limits

| Parameter | Limit | Production Notes |
| :--- | :--- | :--- |
| **Max storage capacity** | 64 TB per instance | Available on SSD persistent disks |
| **Max RAM per instance** | 624 GiB | `db-custom-96-638976` tier |
| **Max connections** | Up to 4,000 (Postgres) / 10,000 (MySQL) | Dependent on instance RAM tier |
| **Failover transition time** | 60 – 120 seconds | Applications must implement retry loops |
| **Read replicas per primary** | Up to 10 read replicas | Replicas do not support automatic failover |

---

## References

* **Homepage:** https://cloud.google.com/sql
* **Documentation:** https://cloud.google.com/sql/docs
* **Cloud SQL Auth Proxy:** https://cloud.google.com/sql/docs/postgres/sql-proxy
* **IAM Database Authentication:** https://cloud.google.com/sql/docs/postgres/authentication
* **Pricing:** https://cloud.google.com/sql/pricing

---

## Pricing Examples

### Scenario 1: Production High-Availability PostgreSQL Cluster
* Instance shape: `db-custom-4-16384` (4 vCPU, 16 GB RAM).
* High Availability (`REGIONAL` tier) doubles compute and disk costs for synchronous standby.
* Compute: 2 × $155.00 / month = $310.00.
* Storage: 200 GB Regional SSD = 200 × $0.34 / GB = $68.00.
* Backups: 200 GB retained = ~$16.00.
* **Total Cost:** **~$394.00 / month**.

### Scenario 2: High-Volume E-Commerce DB with Read Replicas
* 1 Regional Primary (`db-custom-8-32768`) + 2 Zonal Read Replicas (`db-custom-4-16384`).
* Primary HA compute + disk (500 GB SSD): ~$780.00.
* 2 Read Replicas compute (2 × $155 = $310) + disk (2 × 500 GB @ $0.17 = $170): $480.00.
* **Total Cost:** $780 + $480 = **~$1,260.00 / month**.

---

## Nuggets & Gotchas

1. **Storage Can Never Be Downsized:** Cloud SQL allows you to increase disk size on the fly with zero downtime. However, it is physically **impossible to downsize a Cloud SQL disk**. If an accidental load test or unindexed bulk insert bloats your disk from 100 GB to 4 TB, you will pay for 4 TB ($680/month) indefinitely until you export the database to a GCS bucket, provision a brand-new instance, and import the data.
2. **Failover Drops All Active TCP Connections:** During a regional failover (~60–120 seconds), the virtual IP moves to the standby node and all active database sockets are severed. If your application connection pool does not test connections on borrow (`testOnBorrow: true` or `maxLifetime: 30m`), the app will continue trying to send queries over dead sockets, resulting in application-wide cascading errors.
3. **IAM Authentication Token Expiration:** IAM database authentication tokens expire after **60 minutes**. When using Cloud SQL Auth Proxy, the proxy handles token renewal automatically in the background. However, if your application manages IAM tokens directly, long-lived pooled connections that exceed 60 minutes will fail authorization upon reconnection.
4. **`max_connections` Memory Allocation Traps:** Cloud SQL scales `max_connections` proportionally with RAM. However, each PostgreSQL backend process consumes up to `work_mem` (default 4MB) for sorting and hashing. If 500 concurrent connections execute memory-intensive aggregations simultaneously, the database instance will run out of memory, triggering the Linux kernel Out-Of-Memory (`oom-killer`) to kill the Postgres master process.
5. **Private IP Cloud SQL Requires Service Networking Peering:** Provisioning Cloud SQL with a Private IP does not place the database VM directly inside your subnet. Instead, Google creates the database inside a Google-managed tenant VPC and bridges it to your VPC using a **Service Networking Peering** connection with an allocated IP range (e.g. `/24` or `/20`).
