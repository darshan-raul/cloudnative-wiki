---
title: AWS Glue
description: AWS Glue — managed ETL, crawlers, schema inference, Glue Data Catalog, job bookmarks, and Glue Studio visual ETL
tags:
  - aws
  - analytics
  - glue
---

# AWS Glue

Glue is AWS's managed ETL (Extract, Transform, Load) service. It has three main components: a Data Catalog (metastore for S3-based data), crawlers (schema inference), and jobs (data transformation logic). It's the backbone of most AWS data lakes.

## Glue Data Catalog

The Glue Data Catalog is a central metadata repository. It stores table definitions (schema, location, partition info) that are used by Athena, Redshift Spectrum, EMR, and Glue itself.

### Create Table Manually

```sql
CREATE TABLE sales (
  sale_id BIGINT,
  product_id INT,
  customer_id INT,
  sale_date STRING,
  amount DECIMAL(10,2)
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://my-data-lake/sales/'
TBLPROPERTIES ('skip.header.line.count'='1');
```

### Catalog Integration

```python
import boto3

glue = boto3.client('glue')

# Create database
glue.create_database(
    Name='production',
    Description='Production data lake tables',
    TargetDatabase={
        'DatabaseName': 'production',
        'CatalogId': '123456789012'
    }
)

# Create table
glue.create_table(
    DatabaseName='production',
    TableInput={
        'Name': 'sales',
        'StorageDescriptor': {
            'Columns': [
                {'Name': 'sale_id', 'Type': 'bigint'},
                {'Name': 'product_id', 'Type': 'int'},
                {'Name': 'sale_date', 'Type': 'string'}
            ],
            'Location': 's3://my-data-lake/sales/',
            'InputFormat': 'org.apache.hadoop.mapred.TextInputFormat',
            'OutputFormat': 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
            'SerdeInfo': {
                'SerializationLibrary': 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe',
                'Parameters': {'field.delim': ','}
            }
        },
        'TableType': 'EXTERNAL_TABLE'
    }
)
```

## Crawlers

Crawlers automatically discover schema by inspecting data in S3. They can handle CSV, JSON, Parquet, Avro, and more.

```python
glue.create_crawler(
    Name='sales-crawler',
    Role='arn:aws:iam::123456789:role/GlueCrawlerRole',
    DatabaseName='production',
    Targets={
        'S3Targets': [
            {'Path': 's3://my-data-lake/sales/', 'Exclusions': ['**/*.tmp']}
        ],
        'JdbcTargets': [],
        'DynamoDBTargets': []
    },
    Schedule='cron(0 1 * * ? *)',  # Run daily at 1 AM
    SchemaChangePolicy={
        'DeleteBehavior': 'LOG',  # LOG = don't delete, UPDATE = update in place
        'UpdateBehavior': 'UPDATE_IN_DATABASE'
    },
    Configuration='{"Version": 1}',
    TablePrefix='raw_'  # Prefix for tables created by this crawler
)
```

**Crawler behavior:**
1. Connects to the data source
2. Infers schema by sampling files (first 10MB or 10 files, whichever is first)
3. Determines partition structure (e.g., `year=2024/month=06/`)
4. Creates or updates table definition in the Glue Data Catalog
5. Writes to CloudWatch Logs with what it found

**Partition inference:** If your S3 path is `sales/year=2024/month=06/day=01/`, the crawler infers `year`, `month`, `day` as partition columns.

## Glue Jobs

Glue jobs are the ETL logic. You write PySpark or Scala Spark code, and Glue provisions a Spark environment to run it.

### Python Shell Job (simpler, lower cost)

For lighter ETL work, Python Shell jobs run without Spark:

```python
import boto3
import pandas as pd
from io import StringIO

def handler(event, context):
    s3 = boto3.client('s3')
    
    # Read CSV from S3
    obj = s3.get_object(Bucket='my-bucket', Key='sales/data.csv')
    df = pd.read_csv(obj['Body'])
    
    # Transform: filter, aggregate
    df['sale_date'] = pd.to_datetime(df['sale_date'])
    monthly = df.groupby(df['sale_date'].dt.to_period('M')).agg({
        'amount': 'sum',
        'sale_id': 'count'
    }).reset_index()
    
    # Write to S3
    output = monthly.to_csv(index=False)
    s3.put_object(Bucket='my-bucket', Key='sales/summary/monthly.csv', Body=output)
    
    return {'status': 'done'}
```

### Spark Job (full ETL)

```python
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum, count, to_date

spark = SparkSession.builder.getOrCreate()

# Read from Glue catalog
df = spark.read.format('parquet') \
    .option('path', 's3://my-data-lake/sales/') \
    .load()

# Transform
monthly_sales = df \
    .withColumn('sale_month', to_date(col('sale_date'), 'yyyy-MM-dd')) \
    .groupBy('sale_month', 'product_id') \
    .agg(
        sum('amount').alias('total_revenue'),
        count('sale_id').alias('transaction_count')
    ) \
    .orderBy('sale_month')

# Write output
monthly_sales.write \
    .format('parquet') \
    .option('path', 's3://my-data-lake/sales/summary/monthly=2024-06/') \
    .partitionBy('sale_month') \
    .mode('overwrite') \
    .save()
```

## Job Bookmarks

Job bookmarks let Glue track what data has already been processed, so subsequent job runs only process new data.

```python
# Glue Spark job with bookmarks
df = spark.read.format('parquet') \
    .option('path', 's3://my-data-lake/sales/') \
    .option('useGlueParquetOutputs', 'true') \
    .load()

# Glue tracks the last successfully processed file
# On next run, only new files are processed
```

**Bookmark behavior:**
- Works with S3 sources, JDBC sources
- Tracks the highest timestamp or file key processed
- On next run, filters out already-processed data
- Can be reset if you need to re-process from scratch

**Bookmark options:**
- `jobBookmarkKeys`: Custom keys for bookmark tracking (e.g., partition columns)
- `jobBookmarkKeysSortOrder`: ASC or DESC for bookmark key ordering

## Glue Studio

Glue Studio provides a visual interface for building ETL jobs. You drag and drop transformers, configure sources and destinations, and Glue generates the underlying PySpark code.

**Visual job flow:**
```
S3 (source) → Filter → Transform → S3 (destination)
              ↓
         ApplyMapping (rename/cast columns)
              ↓
         DropFields
```

Glue Studio is useful for:
- Non-programmers building ETL pipelines
- Quick prototyping before writing production code
- Visual debugging of job logic

## Glue Triggers and Workflows

Glue workflows orchestrate multiple jobs, crawlers, and triggers:

```python
# Create a workflow
glue.create_workflow(Name='etl-workflow')

# Add trigger: run job after crawler completes
glue.create_trigger(
    Name='crawler-to-etl',
    WorkflowName='etl-workflow',
    Type='CONDITIONAL',
    Actions=[{'JobName': 'sales-etl-job'}],
    Predicate={
        'Logical': 'AND',
        'Conditions': [{
            'LogicalOperator': 'EQUALS',
            'JobName': 'sales-crawler',
            'State': 'SUCCEEDED'
        }]
    }
)
```

**Workflows handle:**
- Sequential dependencies (crawler → ETL → validation)
- Parallel job execution
- Event-based triggers (S3 object arrival, CloudWatch schedule)

## Data Catalog Integration with Other Services

### Athena

```sql
-- Tables created in Glue are immediately available in Athena
SELECT * FROM production.sales WHERE year = '2024';
```

### Redshift Spectrum

```sql
-- External tables in Glue can be queried via Redshift Spectrum
SELECT * FROM spectrum.sales WHERE sale_date > '2024-01-01';
```

### EMR

```python
# Spark reads Glue catalog tables
df = spark.sql("SELECT * FROM production.sales LIMIT 100")
```

## Schema Registry (AWS Glue Schema Registry)

AWS Glue Schema Registry stores and validates schemas for streaming data (Kinesis, Kafka). It prevents incompatible schemas from breaking downstream consumers.

```python
import awscharm

client = awscharm.client('glue')

# Register schema
client.create_registry(RegistryName='my-registry')
client.create_schema(
    RegistryName='my-registry',
    SchemaName='sales-event',
    DataFormat='AVRO',
    Compatibility='BACKWARD_COMPATIBLE',
    SchemaDefinition=json.dumps(schema)
)

# Use with Kinesis
# Schemas are checked on produce/consume — incompatible events are rejected
```

## Cost Optimization

- **Glue Data Catalog:** $1/million table entries, $1/million accesses
- **Crawler:** Charged by DPU-hour (0.0625-10 DPUs, 1 DPU = 4 vCPU)
- **Job:** Charged by DPU-hour while running. Python Shell jobs are cheaper than Spark jobs.
- **Serverless:** Glue Serverless runs jobs without provisioning DPUs — charged per second based on data processed

**Cost tips:**
- Use Python Shell jobs for simple transformations (CSV parsing, filtering)
- Use Glue bookmarks to avoid re-processing data
- Set job timeout to avoid runaway jobs
- Use Glue Studio to visually build before coding

## References

- **Homepage:** https://aws.amazon.com/glue/
- **Documentation:** https://docs.aws.amazon.com/glue/latest/dg/
- **Pricing:** https://aws.amazon.com/glue/pricing/

## Pricing Examples

**Scenario 1:** A daily ETL job processing 5GB of CSV data, transforming to Parquet, and loading to S3 data lake. Glue Python Shell job (2 DPUs, 15 minutes): 2 × 0.0625 DPU-hr × $0.44/DPU-hr × 0.25 hr = $0.0137 per run × 30 = $0.41/month. vs a Spark job (10 DPUs, 5 minutes): 10 × 0.0625 × $0.44 × 0.083 = $0.023 per run × 30 = $0.69/month. Python Shell is 50% cheaper for simple transforms.

**Scenario 2:** A Glue crawler running weekly on 50K tables across 500 databases. 1 DPU, 4 hours per run: 0.0625 × $0.44 × 4 = $0.11 per run × 4 runs/month = $0.44/month for crawler. Plus Data Catalog: 50K table entries × $1/million = $0.05/month. Total: ~$0.50/month for catalog infrastructure.

## Nuggets & Gotchas

- **Glue jobs are billed per second with a 1-minute minimum:** A job that runs 30 seconds is billed for 1 minute. A job that runs 61 seconds is billed for 2 minutes. Optimize for batch efficiency.
- **Glue bookmarks add a `ompany/_good` prefix to data:** The bookmarks state is stored in S3 in a hidden prefix. If you delete the bookmark data, Glue re-processes all historical data. Don't manually delete the bookmark S3 prefix.
- **Glue Spark jobs allocate 10GB executor memory per DPU:** 10 DPUs = 100GB executor memory. If your data is 20GB per partition, 10 DPUs can handle 5 partitions in parallel. For large data, increase DPUs but also tune `maxBatches` in the dynamic frame.
- **Glue Serverless DPUs are charged per second:** Unlike provisioned Glue (billed per DPU-hour), Glue Serverless is billed per second with a 1-minute minimum. For bursty workloads, serverless is more cost-efficient.
- **Glue Studio visual jobs generate Spark code:** The visual editor generates Python/Scala Spark code. You can inspect and modify the generated code — it's real Spark, not a proprietary abstraction.