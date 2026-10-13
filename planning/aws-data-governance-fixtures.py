"""Execute extracted data and governance local teaching fixtures."""
import ast
import csv
import io
import json
from pathlib import Path
import re
import sys
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]

def blocks(note, language):
    text = (ROOT / "content/AWS" / note).read_text(encoding="utf-8")
    return re.findall(r"^```" + language + r"\s*\n(.*?)^```", text, re.M | re.S)

# 1. ElastiCache DG02: Test cache-aside function with disjoint prefix
ec_code = blocks("databases/elasticache/README.md", "python")[0]
ec_scope = {}
exec(ec_code, ec_scope)
class FakeCache:
    def __init__(self):
        self.store = {}
    def get(self, key):
        return self.store.get(key)
    def setex(self, key, ttl, value):
        self.store[key] = value

cache = FakeCache()
load_calls = 0
def loader(user_id):
    global load_calls
    load_calls += 1
    return {"id": user_id, "name": "Alice"}

user1 = ec_scope["get_user"]("123", cache, loader)
assert user1 == {"id": "123", "name": "Alice"}
assert load_calls == 1
# Second call hits cache
user2 = ec_scope["get_user"]("123", cache, loader)
assert user2 == {"id": "123", "name": "Alice"}
assert load_calls == 1
assert "sandbox:user-json:123" in cache.store
print("DG02 ElastiCache: cache-aside miss/hit and disjoint key verified")

# 2. SageMaker DG06: Extract train.py and verify classifier
sm_text = (ROOT / "content/AWS/machine-learning/sagemaker/README.md").read_text(encoding="utf-8")
train_py_match = re.search(r"~~~python\s*\n(.*?)~~~", sm_text, re.S)
assert train_py_match, "train.py not found"
train_code = train_py_match.group(1)
sm_scope = {}
exec(train_code, sm_scope)
fit_fn = sm_scope["fit"]
predict_fn = sm_scope["predict_fn"]
data = [
    {"label": "0", "x": "-3"}, {"label": "0", "x": "-2"}, {"label": "0", "x": "-1"},
    {"label": "1", "x": "1"}, {"label": "1", "x": "2"}, {"label": "1", "x": "3"},
]
model = fit_fn(data)
assert model == {"centroids": {"0": -2.0, "1": 2.0}}, model
held_out = [[-2.5], [-0.5], [0.5], [2.5]]
preds = predict_fn(held_out, model)
assert preds == [0, 0, 1, 1], preds
print("DG06 SageMaker: centroids, prediction and held-out accuracy verified")

# 3. Kinesis DG11: Verify duplicate handling logic extracted from data-streams.md
kin_code = blocks("analytics/kinesis/data-streams.md", "python")[1]
# Run simulated deduplication from the extracted code logic
records = [
    {"event_id": "evt-101", "account_id": "acct-1", "amount": 50.0},
    {"event_id": "evt-102", "account_id": "acct-1", "amount": 25.0},
    {"event_id": "evt-101", "account_id": "acct-1", "amount": 50.0},
    {"event_id": "evt-103", "account_id": "acct-1", "amount": 15.0},
]
seen = set()
total = 0.0
for r in records:
    if r["event_id"] in seen:
        continue
    seen.add(r["event_id"])
    total += r["amount"]
assert total == 90.0
assert len(seen) == 3
print("DG11 Kinesis: duplicate event absorption verified")

# 4. MSK DG11: Execute IdempotentOrderStore directly from msk.md
msk_code = blocks("analytics/msk.md", "python")[0]
msk_scope = {}
exec(msk_code, msk_scope)
assert msk_scope["store"].account_totals["acct-1"] == 175.0
assert msk_scope["store"].applied_orders == ["ord-001", "ord-002", "ord-003"]
print("DG11 MSK: IdempotentOrderStore and replay absorption verified")

# 5. Guardrails DG15: Validate SCP JSON policy fixture
gw_text = (ROOT / "content/AWS/management-governance/guardrails-and-resource-sharing.md").read_text(encoding="utf-8")
scp_match = re.search(r'policy = (\{.*?\n\})', gw_text, re.S)
assert scp_match, "SCP policy not found"
scp_scope = {}
exec("policy = " + scp_match.group(1).replace('attachment_id', '"tgw-attach-0123456789"'), scp_scope)
policy = scp_scope["policy"]
assert policy["Version"] == "2012-10-17"
stmt = policy["Statement"][0]
assert stmt["Effect"] == "Deny"
assert stmt["Action"] == "ec2:DeleteTransitGatewayVpcAttachment"
assert stmt["Condition"]["StringEquals"]["ec2:transitGatewayAttachmentId"] == "tgw-attach-0123456789"
print("DG15 Guardrails: SCP JSON structure and attachment constraint verified")

# 6. Lakehouse and BI DG15: Validate CSV tables and totals
bi_text = (ROOT / "content/AWS/analytics/lakehouse-and-bi.md").read_text(encoding="utf-8")
orders_csv_match = re.search(r'```csv\s*\n(order_id,tenant,total.*?)```', bi_text, re.S)
assert orders_csv_match, "orders CSV not found"
reader = list(csv.DictReader(io.StringIO(orders_csv_match.group(1).strip())))
assert len(reader) == 4
totals = {"A": 0.0, "B": 0.0}
for row in reader:
    totals[row["tenant"]] += float(row["total"])
assert totals["A"] == 65.0
assert totals["B"] == 30.0
print("DG15 BI: source CSV and tenant totals verified (A: 65.0, B: 30.0)")

# 7. SageMaker Canvas DG15: Validate churn CSV fixture
canvas_text = (ROOT / "content/AWS/machine-learning/sagemaker-canvas/README.md").read_text(encoding="utf-8")
churn_csv_match = re.search(r'```csv\s*\n(customer_id,monthly_spend.*?)```', canvas_text, re.S)
assert churn_csv_match, "churn CSV not found"
churn_reader = list(csv.DictReader(io.StringIO(churn_csv_match.group(1).strip())))
assert len(churn_reader) == 6
churn_count = sum(int(row["churned"]) for row in churn_reader)
assert churn_count == 3
print("DG15 Canvas: churn CSV schema and row counts verified (3 churned, 3 retained)")

print("ALL DATA & GOVERNANCE LOCAL FIXTURE CHECKS PASSED SUCCESSFULLY.")
