"""Execute extracted local teaching fixtures, never AWS provisioning code."""
import ast
import hashlib
import json
from pathlib import Path
import re
import sys
from types import ModuleType, SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]


def blocks(note, language):
    text = (ROOT / "content/AWS" / note).read_text()
    return re.findall(r"^```" + language + r"\s*\n(.*?)^```", text, re.M | re.S)


pipeline = blocks("developer-tools/README.md", "python")
app = ModuleType("app")
exec(pipeline[0], app.__dict__)
sys.modules["app"] = app
tests = {"__name__": "fixture_tests"}
exec(pipeline[1], tests)
suite = unittest.defaultTestLoader.loadTestsFromTestCase(tests["GreetingTest"])
result = unittest.TextTestRunner(verbosity=2).run(suite)
assert result.wasSuccessful()

files = {"app.py": pipeline[0]}


class MemoryPath:
    def __init__(self, name):
        self.name = name

    def read_text(self, **_):
        return files[self.name]

    def read_bytes(self):
        return files[self.name].encode()

    def write_text(self, text, **_):
        files[self.name] = text


# Execute the actual packaging body with in-memory files and no credentials.
tree = ast.parse(pipeline[2])
tree.body = [node for node in tree.body if not isinstance(node, (ast.Import, ast.ImportFrom))]
exec(compile(tree, "extracted-package.py", "exec"), {
    "Path": MemoryPath, "hashlib": hashlib, "json": json,
    "os": SimpleNamespace(environ={"PIPELINE_LAB_EXECUTION_ROLE_ARN": "arn:aws:iam::123456789012:role/Lab"}),
})
template = json.loads(files["template.json"])
configuration = json.loads(files["configuration.json"])
assert template["Resources"]["Greeting"]["Properties"]["Handler"] == "index.handler"
assert template["Resources"]["Greeting"]["DependsOn"] == "Logs"
assert configuration["Parameters"]["ExecutionRoleArn"].endswith(":role/Lab")
scope = {}
exec(template["Resources"]["Greeting"]["Properties"]["Code"]["ZipFile"], scope)
assert scope["handler"]({"name": "learner"}, object()) == {"message": "Hello, learner", "version": "v1"}

# Demonstrate that the documented runtime-only failure passes local tests but
# fails the post-deploy comparison: this must not be claimed as auto rollback.
bad = pipeline[0].replace(
    'return {"message": f"Hello, {event[\'name\']}", "version": VERSION}',
    'if context is not None:\n        return {"message": "wrong", "version": VERSION}\n'
    '    return {"message": f"Hello, {event[\'name\']}", "version": VERSION}',
)
assert bad != pipeline[0]
bad_scope = {}
exec(bad, bad_scope)
assert bad_scope["handler"]({"name": "learner"}, None) == scope["handler"]({"name": "learner"}, None)
assert bad_scope["handler"]({"name": "learner"}, object()) != scope["handler"]({"name": "learner"}, None)
print("Pipeline: unit inputs, template/config, index handler and runtime-health failure verified")

lambda_code = next(code for code in blocks("compute/lambda/README.md", "python") if "def handler" in code)
lambda_scope = {}
exec(lambda_code, lambda_scope)
assert json.loads(lambda_scope["handler"]({"name": "AWS learner"}, None)["body"]) == {"message": "Hello, AWS learner"}
try:
    lambda_scope["handler"]({"name": 42}, None)
except ValueError:
    pass
else:
    raise AssertionError("Lambda invalid input accepted")
print("Lambda: actual greeting and validation failure verified")

backup_tree = ast.parse(blocks("reliability/backup-and-recovery.md", "python")[0])
wait_tree = ast.Module(body=[n for n in backup_tree.body if isinstance(n, ast.FunctionDef)], type_ignores=[])


class FakeClock:
    value = 0

    def monotonic(self):
        return self.value

    def sleep(self, seconds):
        self.value += seconds


clock = FakeClock()
wait_scope = {"time": clock}
exec(compile(wait_tree, "actual-wait-job", "exec"), wait_scope)
wait = wait_scope["wait_job"]
responses = iter([{"State": "CREATED"}, {"State": "RUNNING"}, {"State": "COMPLETED", "RecoveryPointArn": "point"}])
calls = []


def describe(**kwargs):
    calls.append(kwargs)
    return next(responses)


assert wait(describe, "job", "BackupJobId", "State", "COMPLETED", {"FAILED", "PARTIAL"})["RecoveryPointArn"] == "point"
assert calls == [{"BackupJobId": "job"}] * 3
for state in ("FAILED", "PARTIAL"):
    try:
        wait(lambda **_: {"State": state}, "job", "BackupJobId", "State", "COMPLETED", {"FAILED", "PARTIAL"})
    except RuntimeError:
        pass
    else:
        raise AssertionError("Failed/partial backup treated as successful")
clock.value = 0
try:
    wait(lambda **_: {"Status": "RUNNING"}, "restore", "RestoreJobId", "Status", "COMPLETED", {"FAILED"})
except TimeoutError:
    assert clock.value >= 1800
else:
    raise AssertionError("Unbounded wait")
assert wait(lambda **_: {"Status": "COMPLETED", "CreatedResourceArn": "new-volume"}, "restore", "RestoreJobId", "Status", "COMPLETED", {"FAILED"})["CreatedResourceArn"] == "new-volume"
print("Backup: actual polling success/failure/partial/timeout and response-field contracts verified")
print("No AWS calls, credentials, filesystem artifacts or cloud execution claims")
