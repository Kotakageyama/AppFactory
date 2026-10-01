"""Validate the documented, deliberately limited app.yaml format."""
import json
import re
import shlex
import sys
from pathlib import Path


def scalar(raw):
    if raw.startswith('"'):
        value, end = json.JSONDecoder().raw_decode(raw)
        if not isinstance(value, str) or raw[end:].strip().split("#", 1)[0].strip():
            raise ValueError("invalid quoted scalar")
        return value
    if raw.startswith("'"):
        match = re.fullmatch(r"'((?:[^']|'')*)'\s*(?:#.*)?", raw)
        if not match:
            raise ValueError("invalid quoted scalar")
        return match[1].replace("''", "'")
    value = re.split(r"\s+#", raw, maxsplit=1)[0].strip()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", value):
        raise ValueError("unsupported scalar; use a simple value or quotes")
    return value


def load(path):
    fields, common, seen_sections = {}, [], set()
    section, in_common = None, False
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "\t" in line:
            raise ValueError(f"line {number}: tabs are unsupported")
        match = re.fullmatch(r"( *)([a-z_]+):(?: +(.*))?", line)
        if match:
            indent, key, raw = match.groups()
            depth = len(indent)
            if depth == 0 and key in {"gcp", "cloud_run", "secrets"} and (raw is None or raw.startswith("#")):
                if key in seen_sections:
                    raise ValueError(f"duplicate section: {key}")
                seen_sections.add(key)
                section, in_common = key, False
                continue
            if depth == 2 and section == "secrets" and key == "common":
                if "secrets.common" in fields:
                    raise ValueError("duplicate common list")
                list_value = re.split(r"\s+#", raw, maxsplit=1)[0].strip() if raw is not None else None
                if list_value not in (None, "[]") and not list_value.startswith("#"):
                    raise ValueError("common must be a block list or []")
                fields["secrets.common"] = ""
                in_common = list_value != "[]"
                continue
            if depth == 0 and key == "name":
                full_key = key
                section, in_common = None, False
            elif depth == 2 and section:
                full_key = f"{section}.{key}"
                in_common = False
            else:
                raise ValueError(f"line {number}: unsupported nesting or key")
            if raw is None or full_key in fields:
                raise ValueError(f"missing value or duplicate key: {full_key}")
            fields[full_key] = scalar(raw)
        elif in_common and line.startswith("    - "):
            common.append(scalar(line[6:]))
        else:
            raise ValueError(f"line {number}: unsupported YAML syntax")
    mapping = {
        "name": "APP_NAME", "gcp.project": "GCP_PROJECT", "gcp.region": "GCP_REGION",
        "gcp.artifact_repository": "ARTIFACT_REPOSITORY", "cloud_run.cpu": "CPU",
        "cloud_run.memory": "MEMORY", "cloud_run.min_instances": "MIN_INSTANCES",
        "cloud_run.max_instances": "MAX_INSTANCES", "cloud_run.allow_unauthenticated": "ALLOW_UNAUTHENTICATED",
        "secrets.database_secret": "DATABASE_SECRET", "secrets.common": "COMMON_SECRETS",
    }
    if set(fields) != set(mapping):
        raise ValueError(f"missing keys: {sorted(set(mapping) - set(fields))}; unknown keys: {sorted(set(fields) - set(mapping))}")
    patterns = {
        "name": r"[a-z][a-z0-9-]{0,24}[a-z0-9]",
        "gcp.project": r"[a-z][a-z0-9-]{4,28}[a-z0-9]",
        "gcp.region": r"[a-z]+-[a-z]+[0-9]+",
        "gcp.artifact_repository": r"[a-z][a-z0-9_-]{0,62}",
        "cloud_run.cpu": r"(?:0\.[0-9]*[1-9][0-9]*|[1-9][0-9]*)", "cloud_run.memory": r"[1-9][0-9]*(?:Mi|Gi)",
        "cloud_run.min_instances": r"(?:0|[1-9][0-9]*)", "cloud_run.max_instances": r"[1-9][0-9]*",
        "cloud_run.allow_unauthenticated": r"(?:true|false)",
        "secrets.database_secret": r"[A-Za-z_][A-Za-z0-9_]{0,254}",
    }
    for key, pattern in patterns.items():
        if not re.fullmatch(pattern, fields[key]):
            raise ValueError(f"invalid value for {key}")
    if int(fields["cloud_run.min_instances"]) > int(fields["cloud_run.max_instances"]):
        raise ValueError("min_instances must not exceed max_instances")
    if len(common) != len(set(common)) or any(not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,254}", s) for s in common):
        raise ValueError("common secrets must be unique environment variable names")
    if fields["secrets.database_secret"] in common:
        raise ValueError("database secret must not also appear in common")
    fields["secrets.common"] = " ".join(common)
    return {mapping[key]: value for key, value in fields.items()}


if __name__ == "__main__":
    try:
        for key, value in load(sys.argv[1]).items():
            print(f"{key}={shlex.quote(value)}")
    except (ValueError, OSError, IndexError, UnicodeError) as error:
        print(f"ERROR: invalid config/app.yaml: {error}", file=sys.stderr)
        sys.exit(2)
