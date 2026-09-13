import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


MARKER = "{{SCREENSHOTS}}"


def image_path(route, capture):
    slug = re.sub(r"[^a-z0-9]+", "-", route.lower()).strip("-")[:40] or "root"
    digest = hashlib.sha256(json.dumps([route, capture]).encode()).hexdigest()[:16]
    return f"images/{slug}-{digest}.png"


def gh(args, cwd=None):
    try:
        return subprocess.run(["gh", *args], cwd=cwd, text=True, capture_output=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return subprocess.CompletedProcess(args, 1, "", "GitHub CLI unavailable or timed out")


def attachment_capability(repo):
    version = gh(["--version"])
    match = re.search(r"gh version (\d+)\.(\d+)\.(\d+)", version.stdout)
    if version.returncode or not match or tuple(map(int, match.groups())) < (2, 99, 0):
        return False, "GitHub CLI 2.99.0 or newer is required"
    access = gh(["api", f"repos/{repo}", "--jq", ".permissions.push"])
    if access.returncode or access.stdout.strip() != "true":
        return False, "repository push access could not be confirmed"
    return True, ""


def markdown_text(value):
    value = " ".join(value.split())
    return html.escape(value, quote=False).replace("|", "&#124;").replace("[", "&#91;").replace("]", "&#93;").replace("\\", "&#92;").replace("`", "&#96;").replace("*", "&#42;").replace("_", "&#95;")


def screenshot_section(run, records):
    available = []
    for record in records:
        path = run / image_path(record["route"], record["capture"])
        if path.is_file() and not path.is_symlink() and path.stat().st_size:
            available.append(record)
    available.sort(key=lambda record: record["status"] == "pass")
    selected, omitted = available[:50], available[50:]
    rows = ["### Screenshots", "", "| Route | Capture | Screenshot |", "|-------|---------|------------|"] if selected else ["### Screenshots", ""]
    args = []
    for record in selected:
        route, capture = record["route"], record["capture"]
        path = image_path(route, capture)
        alt = f"Screenshot of {route} ({capture}; {record['status']})"
        rows.append(f"| {markdown_text(route)} | {markdown_text(capture)} | ![{markdown_text(alt)}]({path}) |")
        args.extend(["--attach", f"{path}#{' '.join(alt.split())}"])
    if omitted:
        failures = sum(record["status"] != "pass" for record in omitted)
        rows.extend(["", f"{len(omitted)} screenshots omitted by the 50-file attachment limit ({failures} non-passing); passing captures dropped first."])
    missing = len(records) - len(available)
    if missing:
        rows.extend(["", f"{missing} screenshots unavailable on disk; visual findings remain above."])
    if not records:
        rows.append("No screenshots captured.")
    return "\n".join(rows), args


def post(run, records, body, repo, number, kind="pr"):
    if body.count(MARKER) != 1:
        raise ValueError("Comment body must contain exactly one {{SCREENSHOTS}} marker")
    section, attachments = screenshot_section(run, records)
    can_attach, reason = attachment_capability(repo) if attachments else (False, "")
    if attachments and not can_attach:
        section = f"### Screenshots\n\nScreenshots unavailable: {reason}."
        attachments = []
    body_path = run / "comment-post.md"
    body_path.write_text(body.replace(MARKER, section))
    args = [kind, "comment", number, "--repo", repo, "--body-file", body_path.name]
    result = gh([*args, *attachments], cwd=run)
    if result.returncode and attachments:
        body_path.write_text(body.replace(MARKER, "### Screenshots\n\nScreenshots unavailable: attachment upload failed; posting text-only evidence."))
        result = gh(args, cwd=run)
    if result.returncode:
        print("Evidence comment could not be posted; verification verdict is unchanged.")
    elif result.stdout:
        print(result.stdout.strip())
    return result.returncode


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init")
    init.add_argument("--head", required=True)
    for command in ("path", "record"):
        item = commands.add_parser(command)
        item.add_argument("--run", type=Path, required=True)
        item.add_argument("--route", required=True)
        item.add_argument("--capture", required=True)
        if command == "record":
            item.add_argument("--status", choices=["pass", "fail", "partial", "uninspected"], required=True)
    poster = commands.add_parser("post")
    poster.add_argument("--run", type=Path, required=True)
    poster.add_argument("--body-file", type=Path, required=True)
    poster.add_argument("--repo", required=True)
    poster.add_argument("--number", required=True)
    poster.add_argument("--kind", choices=["pr", "issue"], default="pr")
    args = parser.parse_args()
    if args.command == "init":
        if not re.fullmatch(r"[a-fA-F0-9]{7,64}", args.head):
            parser.error("--head must be a hexadecimal commit SHA")
        base = os.environ.get("TMPDIR") or os.environ.get("TMP") or os.environ.get("TEMP") or tempfile.gettempdir()
        run = Path(tempfile.mkdtemp(prefix=f"screenshot-evidence-{args.head[:12]}-", dir=base)).resolve()
        (run / "images").mkdir()
        (run / "manifest.json").write_text("[]\n")
        print(run)
        return 0
    run = args.run.resolve()
    if args.command == "path":
        print(run / image_path(args.route, args.capture))
        return 0
    manifest = run / "manifest.json"
    records = json.loads(manifest.read_text())
    if args.command == "record":
        record = {"route": args.route, "capture": args.capture, "status": args.status}
        records = [old for old in records if (old["route"], old["capture"]) != (args.route, args.capture)]
        records.append(record)
        manifest.write_text(json.dumps(records, indent=2) + "\n")
        return 0
    return post(run, records, args.body_file.read_text(), args.repo, args.number, args.kind)


if __name__ == "__main__":
    raise SystemExit(main())
