import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


REPOSITORY = Path(__file__).resolve().parents[1]


@pytest.fixture
def runtime(tmp_path):
    """Use copied entry scripts and a fake Docker CLI; never contact a daemon."""
    for directory in ("scripts", "airflow", "eventsim/examples", "bin"):
        (tmp_path / directory).mkdir(parents=True, exist_ok=True)
    for name in ("airflow_startup.sh", "eventsim_startup.sh"):
        shutil.copy(REPOSITORY / "scripts" / name, tmp_path / "scripts" / name)
    docker = tmp_path / "bin/docker"
    docker.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, sys\n"
        "with open(os.environ['STREAMIFY_DOCKER_LOG'], 'a') as f:\n"
        "    f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        "if sys.argv[1:2] == ['ps'] and os.getenv('STREAMIFY_EXISTING_CONTAINER'):\n"
        "    print('existing-container')\n"
    )
    docker.chmod(0o755)
    date = tmp_path / "bin/date"
    date.write_text("#!/bin/sh\nprintf '%s\\n' '2026-01-01T00:00:00'\n")
    date.chmod(0o755)
    env = {
        **os.environ,
        "PATH": f"{tmp_path / 'bin'}{os.pathsep}{os.environ['PATH']}",
        "STREAMIFY_DOCKER_LOG": str(tmp_path / "docker-calls.jsonl"),
    }
    return tmp_path, env


def run_script(runtime, name, *args):
    root, env = runtime
    result = subprocess.run(
        ["bash", str(root / "scripts" / name), *args],
        env=env, capture_output=True, text=True,
    )
    log = root / "docker-calls.jsonl"
    calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    return result, calls


@pytest.mark.parametrize(
    ("arguments", "expected"),
    [
        ([], ["compose", "up", "-d"]),
        (["build"], ["compose", "build"]),
        (["init"], ["compose", "run", "--rm", "airflow-init"]),
    ],
)
def test_airflow_operations_are_separate(runtime, arguments, expected):
    result, calls = run_script(runtime, "airflow_startup.sh", *arguments)
    assert result.returncode == 0, result.stderr
    assert calls == [expected]


def test_eventsim_build_does_not_start_a_container(runtime):
    result, calls = run_script(runtime, "eventsim_startup.sh", "build")
    assert result.returncode == 0, result.stderr
    assert calls == [["build", "-t", "events:1.0", "."]]


def test_eventsim_uses_runtime_parameters_and_mounts_config_without_building(runtime):
    root, _ = runtime
    (root / "eventsim/.env").write_text(
        "EVENTSIM_USERS=42\n"
        "EVENTSIM_KAFKA_BOOTSTRAP_SERVERS=broker.example.test:9092\n"
        "EVENTSIM_CONFIG='examples/custom config.json'\n"
    )
    result, calls = run_script(runtime, "eventsim_startup.sh")
    assert result.returncode == 0, result.stderr
    assert not any(call[0] == "build" for call in calls)
    run = next(call for call in calls if call[0] == "run")
    assert run[run.index("--nusers") + 1] == "42"
    assert run[run.index("--kafkaBrokerList") + 1] == "broker.example.test:9092"
    assert run[run.index("-c") + 1] == "examples/custom config.json"
    assert run[run.index("--mount") + 1].endswith("dst=/opt/eventsim/examples,readonly")


def test_eventsim_does_not_replace_an_existing_container(runtime):
    _, env = runtime
    env["STREAMIFY_EXISTING_CONTAINER"] = "1"
    result, calls = run_script(runtime, "eventsim_startup.sh")
    assert result.returncode == 1
    assert "already exists" in result.stderr
    assert all(call[0] == "ps" for call in calls)
