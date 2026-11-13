#!/usr/bin/env python3
"""Check a device-proof run's screen recordings against its screenshots.

Usage: check.py <run.xcresult> <out-dir>

Every screenshot taken through `DeviceProofCapture` attaches `<step>.frame.json`
(when it was taken, the layout the app reported) next to the upright PNG
`<step>`; the calibration tests also attach `<combination>.pattern.json`
(the card's pixel samples). For every test with a screen recording, and every
capture in it, this script:

1. takes the recording's frame at the capture's time
   (`capturedAt - recording start`, the start read from the mp4's
   `creation_time`, the attachment timestamp as the fallback). iOS recordings
   are variable-frame-rate: a still screen ends the file early, and a capture
   after the last frame uses the last frame;
2. scores the four rotations of that frame, each scaled to the screen's pixel
   size, against the upright screenshot by mean absolute pixel error on a
   small grayscale copy, and keeps the lowest; it must be at least
   ROTATION_ERROR_RATIO times lower than the next and agree with the best
   SSIM. (The card's solid samples alone cannot choose: a wrong rotation
   stretched to shape still lands most of them. Plain SSIM cannot either on
   a mostly dark chat screen: every rotation scores ~0.95 there, measured
   2026-11-13, while the error ratio is still 2.2-3.7x, 560x on the card.)
3. checks the card samples marked `checkInVideo` on that frame (calibration);
4. notes how the raw recording is stored (rotation, stretch): on the iPad the
   recorder keeps the panel's native portrait canvas and SCALES a landscape
   screen into it (1.78x, measured 2026-11-13), which no test setting changes;
5. writes `<test>.upright.mp4`, the recording turned and scaled to the screen,
   and verifies EVERY capture against the frame of that upright copy (SSIM).

A capture passes when the upright copy has the screen's size and its frame
matches the screenshot (SSIM >= threshold), the chosen rotation is clear, and
every video sample is within tolerance. Raw-recording notes do not fail it.

Needs ffmpeg/ffprobe (Homebrew) and `xcrun xcresulttool`; no Python packages.
Exit code 0 = every capture passes, 1 = at least one failed, 2 = bad input.
"""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime

VIDEO_TOLERANCE = 40      # per channel; H.264 shifts flat colours a little
SSIM_THRESHOLD = 0.90
ROTATION_ERROR_RATIO = 2.0  # the chosen rotation's pixel error must be this many times smaller than the next
ROTATIONS = {             # ffmpeg filter turning the stored frame by N degrees clockwise
    0: None,
    90: "transpose=1",
    180: "transpose=1,transpose=1",
    270: "transpose=2",
}


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True)


def export(xcresult: pathlib.Path, out: pathlib.Path) -> list[dict]:
    out.mkdir(parents=True, exist_ok=True)
    proc = run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(xcresult), "--output-path", str(out)])
    if proc.returncode != 0:
        sys.exit(f"check: xcresulttool failed: {proc.stderr.decode()[-400:]}")
    return json.loads((out / "manifest.json").read_text())


def base_name(attachment: dict) -> str:
    """The name the test gave the attachment, without XCTest's `_<n>_<UUID>`.

    XCTest inserts `_0_<UUID>` before the last dotted part of the name and
    keeps the file extension: `x.pattern` becomes `x.pattern_0_<UUID>.json`,
    `x.raw-app` becomes `x_0_<UUID>.raw-app`, `x` becomes `x_0_<UUID>.png`.
    """
    name = attachment.get("suggestedHumanReadableName", "")
    name = re.sub(r"\.(png|json|txt)$", "", name)
    return re.sub(r"_\d+_[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", "", name)


def recording_start(video: pathlib.Path, fallback: float) -> tuple[float, str]:
    proc = run(["ffprobe", "-v", "error", "-show_entries", "format_tags=creation_time", "-of", "default=nw=1:nk=1", str(video)])
    stamp = proc.stdout.decode().strip()
    if stamp:
        dt = datetime.strptime(stamp.replace("Z", "+0000"), "%Y-%m-%dT%H:%M:%S.%f%z")
        return dt.timestamp(), "mp4 creation_time"
    return fallback, "attachment timestamp"


def probe(video: pathlib.Path) -> dict:
    proc = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                "stream=width,height:format=duration", "-of", "json", str(video)])
    data = json.loads(proc.stdout.decode() or "{}")
    stream = (data.get("streams") or [{}])[0]
    return {"width": stream.get("width"), "height": stream.get("height"),
            "duration": float(data.get("format", {}).get("duration", 0))}


def last_frame_time(video: pathlib.Path, duration: float) -> float:
    """The presentation time of the recording's last frame.

    Not the container duration: on a still screen the recorder writes no new
    frame while the file keeps running, so the last frame can sit well before
    the end (simulator, 2026-11-13: last frame at 3.68 s in a 4.37 s file) and
    a seek to `duration - 0.05` decodes nothing.
    """
    proc = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time",
                "-of", "csv=p=0", str(video)])
    times = [float(v) for v in proc.stdout.decode().split() if v.replace(".", "", 1).isdigit()]
    if not times:
        return max(duration - 0.05, 0)
    # `ffmpeg -ss` counts from the stream's first timestamp, not from pts 0:
    # an iPad recording starts at 0.0767 s, so a seek to the raw pts of its
    # last frame (29.993 s) lands 0.077 s past it and decodes nothing (iPad,
    # 2026-11-13). The seek is made on ffmpeg's timeline.
    start = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=start_time",
                 "-of", "csv=p=0", str(video)]).stdout.decode().split(",")[0].strip()
    # (csv prints "0.076667," — a trailing field for the stream's side data.)
    offset = float(start) if start.replace(".", "", 1).isdigit() else 0.0
    # A hair before the frame's own time, so the seek lands on it, not past it.
    return max(max(times) - offset - 0.001, 0)


def filters(rotation: int, width: int, height: int) -> str:
    return ",".join(f for f in (ROTATIONS[rotation], f"scale={width}:{height}") if f)


def frame_png(video: pathlib.Path, at: float, rotation: int, width: int, height: int, path: pathlib.Path) -> bool:
    run(["ffmpeg", "-v", "error", "-y", "-ss", f"{max(at, 0):.3f}", "-i", str(video), "-frames:v", "1",
         "-vf", filters(rotation, width, height), str(path)])
    return path.exists()


def frame_rgb(video: pathlib.Path, at: float, rotation: int, width: int, height: int) -> bytes | None:
    proc = run(["ffmpeg", "-v", "error", "-ss", f"{max(at, 0):.3f}", "-i", str(video), "-frames:v", "1",
                "-vf", filters(rotation, width, height), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
    return proc.stdout if len(proc.stdout) == width * height * 3 else None


def ssim(a: pathlib.Path, b: pathlib.Path) -> float | None:
    proc = run(["ffmpeg", "-v", "info", "-i", str(a), "-i", str(b), "-lavfi", "ssim", "-f", "null", "-"])
    match = re.search(r"All:([0-9.]+)", proc.stderr.decode())
    return float(match.group(1)) if match else None


def gray_small(path: pathlib.Path, landscape: bool) -> bytes:
    size = "240:180" if landscape else "180:240"
    return run(["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"scale={size},format=gray",
                "-f", "rawvideo", "-"]).stdout


def mean_abs_error(a: bytes, b: bytes) -> float | None:
    if not a or len(a) != len(b):
        return None
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def sample_errors(rgb: bytes, width: int, samples: list[dict]) -> list[str]:
    errors = []
    for s in samples:
        i = (s["y"] * width + s["x"]) * 3
        got = rgb[i], rgb[i + 1], rgb[i + 2]
        want = s["expected"]["r"], s["expected"]["g"], s["expected"]["b"]
        if max(abs(a - b) for a, b in zip(got, want)) > VIDEO_TOLERANCE:
            errors.append(f"{s['name']} at ({s['x']},{s['y']}): expected {want}, measured {got}")
    return errors


def write_upright(video: pathlib.Path, rotation: int, width: int, height: int, path: pathlib.Path) -> bool:
    w, h = width - width % 2, height - height % 2          # H.264 needs even sizes
    proc = run(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-vf", filters(rotation, w, h),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-metadata:s:v:0", "rotate=0", str(path)])
    return proc.returncode == 0


def screen_px(layout: dict) -> tuple[int, int]:
    return round(layout["screenWidth"] * layout["scale"]), round(layout["screenHeight"] * layout["scale"])


def screenshot_of(name: str, test: dict, files: pathlib.Path) -> tuple[pathlib.Path | None, str | None]:
    """The upright PNG a capture named `name` attached, and any name collision.

    `base_name` keys attachments by the name the test gave them, so a text
    attachment with a capture's name (a test's `keep("fit-verdicts", ...)`
    beside `capture("fit-verdicts", ...)`) used to replace the screenshot,
    which then failed as "could not decode a recording frame" (iPad,
    2026-11-13). The screenshot is the PNG; the collision is reported by name.
    """
    same = [a for a in test["attachments"] if base_name(a) == name]
    pngs = [a["exportedFileName"] for a in same if a["exportedFileName"].lower().endswith(".png")]
    others = [a["exportedFileName"] for a in same if not a["exportedFileName"].lower().endswith(".png")]
    collision = None
    if len(pngs) > 1:
        collision = f"{len(pngs)} PNG attachments are named '{name}' ({', '.join(pngs)}): which one is the screenshot is ambiguous"
        return None, collision
    if others:
        collision = f"attachment name '{name}' is also used by {', '.join(others)}; the screenshot is the PNG {pngs[0] if pngs else '(none)'}"
    return (files / pngs[0] if pngs else None), collision


def captures_of(test: dict, files: pathlib.Path) -> list[dict]:
    """Every capture of a test: its frame.json, the pattern samples if any, the upright PNG."""
    by_base = {base_name(a): a for a in test["attachments"]}
    patterns = {}
    for base, att in by_base.items():
        if base.endswith(".pattern"):
            capture = json.loads((files / att["exportedFileName"]).read_text())
            patterns[capture["combination"]] = capture
    captures = []
    for base, att in by_base.items():
        if not base.endswith(".frame"):
            continue
        frame = json.loads((files / att["exportedFileName"]).read_text())
        name = frame["name"]
        shot, collision = screenshot_of(name, test, files)
        pattern = patterns.get(name, {})
        captures.append({"name": name, "capturedAt": frame["capturedAt"], "layout": frame["layout"],
                         "samples": [s for s in pattern.get("samples", []) if s.get("checkInVideo")],
                         "screenshot": shot, "collision": collision})
    # Runs from before frame.json existed: the pattern alone describes the capture.
    for name, pattern in patterns.items():
        if not any(c["name"] == name for c in captures):
            shot, collision = screenshot_of(name, test, files)
            captures.append({"name": name, "capturedAt": pattern["capturedAt"], "layout": pattern["layout"],
                             "samples": [s for s in pattern["samples"] if s.get("checkInVideo")],
                             "screenshot": shot, "collision": collision})
    return sorted(captures, key=lambda c: c["capturedAt"])


def check_test(test: dict, files: pathlib.Path, out: pathlib.Path) -> list[dict]:
    captures = captures_of(test, files)
    if not captures:
        return []
    test_name = test["testIdentifier"].split("/")[-1].rstrip("()")
    video_att = next((a for a in test["attachments"] if a["exportedFileName"].endswith(".mp4")), None)
    if video_att is None:
        return [{"test": test_name, "capture": c["name"], "pass": False,
                 "problems": ["no screen recording kept for this test (systemAttachmentLifetime?)"]} for c in captures]
    video = files / video_att["exportedFileName"]
    meta = probe(video)
    start, start_source = recording_start(video, video_att.get("timestamp", 0.0))
    last = last_frame_time(video, meta["duration"])

    rows = []
    for c in captures:
        width, height = screen_px(c["layout"])
        at = c["capturedAt"] - start
        row = {"test": test_name, "capture": c["name"], "interfaceOrientation": c["layout"]["interfaceOrientation"],
               "screen": f"{width}x{height}", "raw_video": f"{meta['width']}x{meta['height']}",
               "recording_start_from": start_source, "frame_at_s": round(at, 2), "problems": [], "raw_recording_notes": []}
        if at < 0:
            row["problems"].append(f"screenshot time {at:.2f}s is before the recording started")
        elif at > meta["duration"]:
            row["frame_rule"] = f"screen unchanged after {meta['duration']:.2f}s: last frame used for t={at:.2f}s"
        t_frame = min(max(at, 0), last)
        row["t_frame"] = t_frame
        if c.get("collision"):
            # Named in the report either way; it fails only when no single PNG
            # can be told to be the screenshot (screenshot is then None).
            row["attachment_notes"] = [c["collision"]]
        if c["screenshot"] is None:
            row["problems"].append(c.get("collision") or "upright screenshot attachment not found")
            rows.append(row)
            continue
        scores, errors_by_rotation = {}, {}
        shot_gray = gray_small(c["screenshot"], width > height)
        for rotation in ROTATIONS:
            candidate = out / f"{c['name']}.raw-frame.rot{rotation}.png"
            if frame_png(video, t_frame, rotation, width, height, candidate):
                score = ssim(c["screenshot"], candidate)
                mae = mean_abs_error(shot_gray, gray_small(candidate, width > height))
                if score is not None and mae is not None:
                    scores[rotation], errors_by_rotation[rotation] = score, mae
        if not scores:
            row["problems"].append("could not decode a recording frame at the screenshot's time")
            rows.append(row)
            continue
        rotation = min(errors_by_rotation, key=errors_by_rotation.get)
        others = sorted(v for k, v in errors_by_rotation.items() if k != rotation)
        ratio = (others[0] / max(errors_by_rotation[rotation], 0.01)) if others else float("inf")
        row.update({"rotation_needed_deg": rotation, "ssim_by_rotation": {f"{k}°": round(v, 4) for k, v in scores.items()},
                    "pixel_error_by_rotation": {f"{k}°": round(v, 2) for k, v in errors_by_rotation.items()},
                    "rotation_error_ratio": round(ratio, 1)})
        if ratio < ROTATION_ERROR_RATIO:
            row["problems"].append(f"rotation is ambiguous (its pixel error is only {ratio:.1f}x below the next rotation's)")
        if max(scores, key=scores.get) != rotation:
            row["problems"].append(f"SSIM prefers {max(scores, key=scores.get)}° but pixel error prefers {rotation}°")
        if rotation != 0:
            row["raw_recording_notes"].append(f"raw recording stored {rotation}° off the shown orientation")
        vw, vh = (meta["width"], meta["height"]) if rotation in (0, 180) else (meta["height"], meta["width"])
        stretch = max(vw / vh, width / height) / min(vw / vh, width / height)
        row["raw_stretch"] = round(stretch, 3)
        if stretch > 1.02:
            row["raw_recording_notes"].append(
                f"raw recording stretched {stretch:.2f}x: stored {meta['width']}x{meta['height']} for a {width}x{height} "
                f"screen (iOS recorder keeps the native portrait canvas); corrected in the upright copy")
        if c["samples"]:
            rgb = frame_rgb(video, t_frame, rotation, width, height)
            errors = sample_errors(rgb, width, c["samples"]) if rgb else ["frame not decoded"]
            row["video_samples"] = f"{len(c['samples']) - len(errors)}/{len(c['samples'])}"
            row["sample_errors"] = errors
            if errors:
                row["problems"].append(f"{len(errors)} calibration sample(s) wrong in the recording frame")
        rows.append(row)

    # One upright copy per test, turned the way its captures agree on.
    chosen = [r["rotation_needed_deg"] for r in rows if "rotation_needed_deg" in r]
    if not chosen:
        return rows
    rotation = Counter(chosen).most_common(1)[0][0]
    if len(set(chosen)) > 1:
        for r in rows:
            r["problems"].append(f"captures of one test disagree on the recording's rotation: {sorted(set(chosen))}")
    width, height = screen_px(captures[-1]["layout"])
    upright = out / f"{test_name}.upright.mp4"
    if not write_upright(video, rotation, width, height, upright):
        for r in rows:
            r["problems"].append("could not write the upright copy")
        return rows
    got = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
               "-of", "csv=p=0", str(upright)]).stdout.decode().strip().replace(",", "x")
    want = f"{width - width % 2}x{height - height % 2}"
    for r, c in zip(rows, captures):
        r["upright_video"] = str(upright)
        r["upright_size"] = got
        if got != want:
            r["problems"].append(f"upright copy is {got}, expected {want}")
        if c["screenshot"] is None or "t_frame" not in r:
            continue
        cw, ch = screen_px(c["layout"])
        check_frame = out / f"{c['name']}.upright-frame.png"
        frame_png(upright, max(r["t_frame"] - 0.05, 0), 0, cw, ch, check_frame)
        score = ssim(c["screenshot"], check_frame)
        r["upright_ssim"] = round(score, 4) if score is not None else None
        if score is None or score < SSIM_THRESHOLD:
            r["problems"].append(f"upright copy vs screenshot SSIM {score} < {SSIM_THRESHOLD}")
    for r in rows:
        r["pass"] = not r["problems"]
    return rows


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    xcresult, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    files = out / "attachments"
    manifest = export(xcresult, files)
    rows = [r for test in manifest for r in check_test(test, files, out)]
    if not rows:
        print("check: no capture (<step>.frame.json / <combination>.pattern.json) in this run", file=sys.stderr)
        return 2
    for r in rows:
        r.setdefault("pass", False)
    (out / "check-report.json").write_text(json.dumps(rows, indent=2, default=str))
    lines = ["| test | capture | app orientation | screen | raw video | rotation (error ratio) | raw stretch | video samples | upright copy | upright SSIM | verdict |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['test']} | {r['capture']} | {r.get('interfaceOrientation')} | {r.get('screen')} | "
                     f"{r.get('raw_video')} | {r.get('rotation_needed_deg')}° ({r.get('rotation_error_ratio')}x) | {r.get('raw_stretch')}x | "
                     f"{r.get('video_samples', '—')} | {r.get('upright_size')} | {r.get('upright_ssim')} | "
                     f"{'PASS' if r['pass'] else 'FAIL: ' + '; '.join(r['problems'])}"
                     f"{''.join(' (note: ' + n + ')' for n in r.get('attachment_notes', []))} |")
    report = "\n".join(lines)
    (out / "check-report.md").write_text(report + "\n")
    print(report)
    return 0 if all(r["pass"] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
