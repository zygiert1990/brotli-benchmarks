#!/usr/bin/env python3
"""Compare the main, jni and ffm targets of brotli-benchmarks runs and draw charts.

For one run directory (docs/<Benchmark>/<run-id>) this writes, into that directory:
  comparison.md                 report: setup, charts, per-case table with verdicts
  comparison-performance.svg    execution time per operation
  comparison-heap.svg           on-heap allocation per operation (-prof gc)
  comparison-native.svg         estimated native allocation per operation (async-profiler nativemem)

Bars are relative to the worst result of their row; labels show the value and the change versus `main`.
With --all, every benchmark's latest run under docs/ is processed and docs/summary.md links them.
"""
from __future__ import annotations

import argparse
import html
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

TARGETS = ("main", "jni", "ffm")
BASELINE = "main"
COLORS = {"main": "#6b7280", "jni": "#2563eb", "ffm": "#ea580c"}
BYTE_PARAMETERS = {"inputSize", "bufferSize", "messageSize", "maxOutputChunkSize"}
HEAP_SUFFIX = ":gc.alloc.rate.norm"


@dataclass(frozen=True)
class Measurement:
    score: float
    error: float | None
    unit: str


@dataclass
class Target:
    name: str
    params: tuple[str, ...] = ()
    time: dict[tuple[str, tuple[str, ...]], Measurement] = field(default_factory=dict)
    heap: dict[tuple[str, tuple[str, ...]], Measurement] = field(default_factory=dict)
    native: dict[str, float] = field(default_factory=dict)  # profile case -> bytes/op


# ---------------------------------------------------------------- parsing

def parse_results(path: Path) -> tuple[tuple[str, ...], dict, dict]:
    """JMH text results: parameter names, then time and heap rows keyed by (method, parameter values)."""
    lines = path.read_text(encoding="utf-8").splitlines()
    header = next((line for line in lines if line.startswith("Benchmark ")), None)
    if header is None:
        raise ValueError(f"No JMH header in {path}")
    names = tuple(re.findall(r"\((\w+)\)", header))
    time, heap = {}, {}
    for line in lines:
        tokens = line.split()
        if len(tokens) < 5 or tokens[0] == "Benchmark" or "." not in tokens[0]:
            continue
        name = tokens[0]
        try:
            mode_index = tokens.index("avgt")
        except ValueError:
            continue
        if ":" in name and not name.endswith(HEAP_SUFFIX):
            continue  # other -prof gc rows (alloc rate, gc.count, ...)
        values = tuple(tokens[1:mode_index])
        rest = tokens[mode_index + 1:]
        # Cnt Score [± Error] Units; JMH prints tiny scores as "≈ 0" or "≈ 10⁻⁴" (taken as 0).
        if rest[1] == "≈":
            score, error = 0.0, None
        else:
            score = float(rest[1].replace(",", ""))
            error = float(rest[3].replace(",", "")) if len(rest) >= 5 and rest[2] == "±" else None
        unit = rest[-1]
        method = name.split(".")[1].split(":")[0]
        if name.endswith(HEAP_SUFFIX):
            heap[(method, values)] = Measurement(score, error, unit)
        else:
            time[(method, values)] = Measurement(score, error, unit)
    if not time:
        raise ValueError(f"No benchmark rows in {path}")
    return names, time, heap


def parse_duration_seconds(value: str) -> float:
    match = re.fullmatch(r"\s*([\d.]+)\s*(ns|us|µs|ms|s|min)\s*", value)
    if not match:
        raise ValueError(f"Unsupported JMH time {value!r}")
    return float(match.group(1)) * {"ns": 1e-9, "us": 1e-6, "µs": 1e-6, "ms": 1e-3, "s": 1.0, "min": 60.0}[match.group(2)]


def native_bytes_per_op(case_dir: Path) -> float:
    """Bytes allocated per operation during the measurement iterations (the window async-profiler records)."""
    rows = re.findall(r"^\s*(\d+)\s+[\d.]+%\s+\d+\s+\S+\s*$",
                      (case_dir / "summary-nativemem.txt").read_text(encoding="utf-8"), re.MULTILINE)
    if not rows:
        raise ValueError(f"No allocation rows in {case_dir / 'summary-nativemem.txt'}")
    allocated = sum(int(row) for row in rows)
    result = json.loads((case_dir / "results-nativemem.json").read_text(encoding="utf-8"))[0]
    metric = result["primaryMetric"]
    if result["mode"] != "avgt" or metric["scoreUnit"] != "us/op":
        raise ValueError(f"Expected avgt in us/op in {case_dir}")
    seconds = parse_duration_seconds(result["measurementTime"]) * int(result["measurementIterations"])
    # avgt is per thread: with several threads, each completes seconds / score operations.
    operations = int(result["threads"]) * seconds * 1e6 / float(metric["score"])
    return allocated / operations


def load_run(run_dir: Path) -> tuple[dict[str, Target], dict[str, str], str]:
    jdk_dirs = sorted(path for path in run_dir.glob("jdk-*") if path.is_dir())
    if len(jdk_dirs) != 1:
        raise ValueError(f"Expected one jdk-* directory in {run_dir}, found {len(jdk_dirs)}")
    targets = {}
    for name in TARGETS:
        target_dir = jdk_dirs[0] / name
        if not (target_dir / "results.txt").is_file():
            continue
        target = Target(name)
        target.params, target.time, target.heap = parse_results(target_dir / "results.txt")
        for case_dir in sorted(path for path in target_dir.iterdir() if path.is_dir()):
            if (case_dir / "summary-nativemem.txt").is_file():
                target.native[case_dir.name] = native_bytes_per_op(case_dir)
        targets[name] = target
    if BASELINE not in targets:
        raise ValueError(f"{run_dir} has no {BASELINE} results")
    return targets, parse_metadata(run_dir / "metadata.txt"), jdk_dirs[0].name


def memory_gb(kilobytes: str) -> str:
    # MemTotal excludes kernel-reserved memory; rounding up gives the installed size.
    return f"{math.ceil(int(kilobytes) / 1024 / 1024)} GB" if kilobytes.isdigit() else kilobytes


def parse_metadata(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    def find(pattern: str) -> str:
        match = re.search(pattern, text, re.MULTILINE)
        return match.group(1).strip() if match else "unknown"
    return {
        "benchmark": find(r"^Benchmark: (.*)$"),
        "mode": find(r"^Mode: (.*)$"),
        "extra": find(r"^Extra JMH arguments: ?(.*)$"),
        "main": find(r"^main: (.*)$"),
        "ffm": find(r"^jni/ffm: (.*)$"),
        "java": find(r"^(OpenJDK Runtime Environment.*|Java\(TM\) SE Runtime Environment.*)$"),
        "cpu": find(r"^Model name:\s*(.*)$"),
        "memory": memory_gb(find(r"^MemTotal:\s*(\d+) kB$")),
        "os": find(r"^(Linux .*)$"),
        "platform": find(r"^Platform: (.*)$"),
    }


# ---------------------------------------------------------------- formatting

def fmt_number(value: float) -> str:
    if value >= 100:
        return f"{value:,.0f}"
    if value >= 10:
        return f"{value:,.1f}"
    return f"{value:,.3f}"


def fmt_measurement(measurement: Measurement, unit: str | None = None) -> str:
    error = f" ± {fmt_number(measurement.error)}" if measurement.error is not None else ""
    return f"{fmt_number(measurement.score)}{error} {unit or measurement.unit}"


def fmt_delta(value: float, baseline: float) -> str:
    if baseline == 0:
        return "n/a" if value else "±0%"
    change = (value / baseline - 1.0) * 100.0
    return f"{change:+.1f}%" if abs(change) >= 0.05 else "±0%"


def verdict(candidate: Measurement, reference: Measurement) -> str:
    """faster / slower when the difference exceeds both errors (JMH's 99.9% intervals), otherwise same."""
    if candidate.error is None or reference.error is None:
        return "no error margin"
    if abs(candidate.score - reference.score) <= candidate.error + reference.error:
        return "same"
    return "faster" if candidate.score < reference.score else "slower"


def case_label(method: str, names: tuple[str, ...], values: tuple[str, ...]) -> str:
    parts = []
    for name, value in zip(names, values):
        unit = (" byte" if value == "1" else " bytes") if name in BYTE_PARAMETERS else ""
        parts.append(f"{name}={value}{unit}")
    return f"{method} · {', '.join(parts)}" if parts else method


def native_label(case: str) -> str:
    if case == "default":
        return "single case"
    prefix, _, value = case.partition("-")
    name = {"method": "", "input": "inputSize", "buffer": "bufferSize", "message": "messageSize",
            "cap": "maxOutputChunkSize"}.get(prefix, prefix)
    if not name:
        return value
    return f"{name}={value} bytes"


# ---------------------------------------------------------------- FFM's own native allocation

# async-profiler doesn't see FFM's malloc downcall (a direct call to libc, past its hook), but its size is exact:
# per wrapper, the out-parameter cells (4 pointer-sized values) plus the input buffer, nothing per call.
STREAM_DEFAULT_BUFFER = 16384
# Decoder.decompress(byte[]) creates a wrapper as large as the compressed input: the profiled cases decompress
# the dataset's text prefix compressed at BenchmarkData.PRODUCTION_QUALITY (4).
COMPRESSED_TEXT_SIZE = {"256": 165, "16384": 3040, "131072": 21317}


def ffm_input_buffer(benchmark: str, case: str) -> int | None:
    """Input buffer of the one wrapper a profiled operation creates; 0 if it creates none; None if unknown."""
    prefix, _, value = case.partition("-")
    if benchmark in ("EncoderLifecycleBenchmark", "DecoderLifecycleBenchmark", "EncoderStreamFlushBenchmark",
                     "DecoderOutputCapBenchmark", "DecoderDictionaryBenchmark"):
        return STREAM_DEFAULT_BUFFER
    if benchmark in ("EncoderOneShotBenchmark", "EncoderStreamBufferSizeBenchmark",
                     "DecoderStreamBufferSizeBenchmark") and prefix in ("input", "buffer"):
        return int(value)
    if benchmark == "DecoderOneShotBenchmark" and prefix == "input":
        return COMPRESSED_TEXT_SIZE.get(value)
    if benchmark == "EncoderDictionaryBenchmark":
        return {"prepareAndCloseDictionary": 0, "compressMessageWithDictionary": STREAM_DEFAULT_BUFFER}.get(value)
    return None


def ffm_own_malloc(benchmark: str, case: str, platform: str) -> int | None:
    buffer = ffm_input_buffer(benchmark, case)
    if buffer is None:
        return None
    if buffer == 0:
        return 0
    pointer = 4 if platform == "linux-armv7" else 8
    return 4 * pointer + buffer


# ---------------------------------------------------------------- charts

def render_bar_chart(path: Path, title: str, targets: list[str], categories: list[str],
                     values: dict[str, list[float]], labels: dict[str, list[str]]) -> None:
    """One group per row, bars relative to the row's worst value."""
    left = 40 + 7.5 * max(len(category) for category in categories)
    plot_width = 600
    # Room for the longest value label after a full-length bar.
    right = 30 + 7.5 * max(len(label) for target in targets for label in labels[target])
    width = round(left + plot_width + right)
    top = 105
    row_height = max(58, 24 * len(targets) + 18)
    height = top + row_height * len(categories) + 75
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        '<style>text{font-family:system-ui,-apple-system,sans-serif;fill:#1f2937}.title{font-size:22px;font-weight:700}'
        '.label{font-size:13px}.tick{font-size:12px;fill:#4b5563}.value{font-size:12px;font-weight:600}</style>',
        f'<text x="{left}" y="32" class="title">{html.escape(title)}</text>',
    ]
    for index, target in enumerate(targets):
        x = left + index * 120
        parts += [f'<rect x="{x}" y="50" width="15" height="15" rx="2" fill="{COLORS[target]}"/>',
                  f'<text x="{x + 22}" y="63" class="label">{html.escape(target)}</text>']
    for tick in range(5):
        x = left + plot_width * tick / 4
        parts += [f'<line x1="{x:.1f}" y1="{top - 12}" x2="{x:.1f}" y2="{height - 48}" stroke="#e5e7eb"/>',
                  f'<text x="{x:.1f}" y="{height - 25}" text-anchor="middle" class="tick">{tick * 25}%</text>']
    parts.append(f'<line x1="{left}" y1="{top - 12}" x2="{left}" y2="{height - 48}" stroke="#6b7280" stroke-width="1.5"/>')
    for row, category in enumerate(categories):
        center = top + row * row_height + row_height / 2
        parts.append(f'<text x="{left - 12}" y="{center + 4:.1f}" text-anchor="end" class="label">{html.escape(category)}</text>')
        for index, target in enumerate(targets):
            bar = max(1.0, values[target][row] / 100.0 * plot_width)
            y = center + (index - (len(targets) - 1) / 2) * 23 - 9
            parts += [f'<rect x="{left}" y="{y:.1f}" width="{bar:.1f}" height="18" rx="2" fill="{COLORS[target]}"/>',
                      f'<text x="{left + bar + 6:.1f}" y="{y + 13:.1f}" class="value">{html.escape(labels[target][row])}</text>']
    parts.append("</svg>")
    path.write_text("\n".join(parts) + "\n", encoding="utf-8")


def chart_rows(targets: dict[str, Target], rows: list, values_of,
               incomplete: dict[str, str] | None = None) -> tuple[dict, dict]:
    """values_of(target, row) -> (value, label text); bars relative to the row's worst, ★ marks the best.

    incomplete maps a target to a note: its values are known to miss something, so it gets the note instead
    of a change versus main and can't be the best of a row.
    """
    incomplete = incomplete or {}
    bars = {name: [] for name in targets}
    labels = {name: [] for name in targets}
    for row in rows:
        values = {name: values_of(target, row) for name, target in targets.items()}
        worst = max(value for value, _ in values.values())
        comparable = [value for name, (value, _) in values.items() if name not in incomplete]
        best = min(comparable) if comparable else None
        baseline = values[BASELINE][0]
        for name, (value, text) in values.items():
            bars[name].append(value / worst * 100.0 if worst else 0.0)
            if name in incomplete:
                labels[name].append(f"{text} ({incomplete[name]})")
                continue
            star = "★ " if best is not None and math.isclose(value, best) else ""
            labels[name].append(f"{star}{text} ({fmt_delta(value, baseline)})")
    return bars, labels


# ---------------------------------------------------------------- report

def compare_run(run_dir: Path) -> dict:
    targets, meta, jdk = load_run(run_dir)
    names = list(targets)
    base = targets[BASELINE]
    keys = [key for key in base.time if all(key in target.time for target in targets.values())]
    categories = [case_label(method, base.params, values) for method, values in keys]

    time_bars, time_labels = chart_rows(targets, keys, lambda t, k: (t.time[k].score, fmt_measurement(t.time[k])))
    render_bar_chart(run_dir / "comparison-performance.svg", "Execution time (bar length relative to row worst)",
                     names, categories, time_bars, time_labels)
    charts = ["comparison-performance.svg"]

    heap_keys = [key for key in keys if all(key in target.heap for target in targets.values())]
    if heap_keys:
        heap_bars, heap_labels = chart_rows(targets, heap_keys,
                                            lambda t, k: (t.heap[k].score, fmt_measurement(t.heap[k], "B/op")))
        render_bar_chart(run_dir / "comparison-heap.svg", "On-heap allocation (bar length relative to row worst)",
                         names, [case_label(m, base.params, v) for m, v in heap_keys], heap_bars, heap_labels)
        charts.append("comparison-heap.svg")

    benchmark = meta["benchmark"] if meta["benchmark"] != "unknown" else run_dir.parent.name
    native_cases = [case for case in base.native if all(case in target.native for target in targets.values())]
    own = {case: ffm_own_malloc(benchmark, case, meta["platform"]) for case in native_cases}
    counted = "ffm" in targets and all(value is not None for value in own.values())

    def native_value(target: Target, case: str) -> tuple[float, str]:
        measured = target.native[case]
        if target.name != "ffm" or not counted or not own[case]:
            return measured, f"{fmt_number(measured)} B/op"
        total = measured + own[case]
        return total, f"{fmt_number(total)} B/op = {fmt_number(measured)} + {fmt_number(own[case])} FFM malloc"

    if native_cases:
        native_bars, native_labels = chart_rows(targets, native_cases, native_value,
                                                None if counted else {"ffm": "brotli only, excludes FFM's own malloc"})
        render_bar_chart(run_dir / "comparison-native.svg", "Estimated native allocation",
                         names, [native_label(case) for case in native_cases], native_bars, native_labels)
        charts.append("comparison-native.svg")

    counts = {"faster": 0, "same": 0, "slower": 0, "no error margin": 0}
    ratios = []
    table = ["| Case | " + " | ".join(names) + " | ffm vs jni | ffm vs main |",
             "|---|" + "---|" * len(names) + "---|---|"]
    for key, label in zip(keys, categories):
        cells = [fmt_measurement(targets[name].time[key]) for name in names]
        row_verdicts = []
        for reference in ("jni", "main"):
            if "ffm" in targets and reference in targets:
                ffm, ref = targets["ffm"].time[key], targets[reference].time[key]
                result = verdict(ffm, ref)
                row_verdicts.append(f"{result} ({fmt_delta(ffm.score, ref.score)})")
                if reference == "jni":
                    counts[result] += 1
                    ratios.append(ffm.score / ref.score)
            else:
                row_verdicts.append("n/a")
        table.append(f"| {label} | " + " | ".join(cells) + " | " + " | ".join(row_verdicts) + " |")

    report = [
        f"# {benchmark} — {jdk}",
        "",
        f"- `main`: {meta['main']}",
        f"- `jni` / `ffm`: {meta['ffm']} (`-Dbrotli4j.backend=jni` / `ffm`)",
        f"- Java: {meta['java']}; host: {meta['os']}, {meta['cpu']}, {meta['memory']}",
        f"- Run: `{run_dir.name}`, mode {meta['mode']}, extra JMH arguments: `{meta['extra'] or 'none'}`",
        "",
        "Bars are relative to the worst result of their row. Labels show the value and the change versus `main`; "
        "negative is better. ★ marks the best result of a row.",
        "",
    ]
    report += [f"![{chart}]({chart})" for chart in charts]
    if native_cases:
        report += ["", "Native allocation is estimated from async-profiler's `nativemem` samples during the "
                   "measurement iterations. The profiler doesn't see `ffm`'s own `malloc` downcall: FFM calls libc's "
                   "`malloc` directly, past the profiler's hook."]
        if counted:
            report[-1] += (" Its size is exact (the out-parameter cells plus the input buffer per wrapper), so `ffm` "
                           "values are the measured value plus that count, labelled `measured + FFM malloc`.")
        else:
            report[-1] += (" Its size isn't known for every case of this run, so `ffm` values cover brotli's "
                           "allocations only, and lower `ffm` values don't mean FFM allocates less.")
    report += ["", "## Execution time", "",
               "`faster` / `slower`: the difference exceeds both JMH error margins (99.9%); otherwise `same`.", ""]
    report += table
    report.append("")
    (run_dir / "comparison.md").write_text("\n".join(report), encoding="utf-8")
    geomean = math.exp(sum(math.log(r) for r in ratios) / len(ratios)) if ratios else float("nan")
    return {"benchmark": benchmark, "run": run_dir, "counts": counts, "geomean": geomean,
            "best": min(ratios, default=float("nan")), "worst": max(ratios, default=float("nan"))}


def latest_runs(docs: Path) -> list[Path]:
    runs = []
    for benchmark in sorted(path for path in docs.iterdir() if path.is_dir()):
        candidates = sorted(path for path in benchmark.iterdir() if (path / "metadata.txt").is_file())
        if candidates:
            runs.append(candidates[-1])
    return runs


def write_summary(docs: Path, results: list[dict]) -> Path:
    lines = ["# Summary: ffm vs jni (execution time)", "",
             "Latest run of each benchmark. Ratio < 1 means FFM is faster; verdicts use the JMH error margins.", "",
             "| Benchmark | Cases | faster | same | slower | geometric mean ffm/jni | best | worst | Report |",
             "|---|---|---|---|---|---|---|---|---|"]
    for result in results:
        counts = result["counts"]
        cases = sum(counts.values())
        link = (result["run"] / "comparison.md").relative_to(docs)
        lines.append(f"| {result['benchmark']} | {cases} | {counts['faster']} | {counts['same']} | {counts['slower']} | "
                     f"{result['geomean']:.2f} | {result['best']:.2f} | {result['worst']:.2f} | [report]({link}) |")
    path = docs / "summary.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_directory", nargs="?", type=Path,
                        help="docs/<Benchmark>/<run-id>, or docs/<Benchmark> for its latest run")
    parser.add_argument("--all", action="store_true", help="process the latest run of every benchmark under --docs")
    parser.add_argument("--docs", type=Path, default=Path(__file__).resolve().parent.parent / "docs")
    args = parser.parse_args()
    if args.all == (args.run_directory is not None):
        parser.error("give either a run directory or --all")
    try:
        if args.all:
            results = [compare_run(run) for run in latest_runs(args.docs)]
            for result in results:
                print(f"Wrote {result['run'] / 'comparison.md'}")
            print(f"Wrote {write_summary(args.docs, results)}")
        else:
            run = args.run_directory
            if not (run / "metadata.txt").is_file():
                # A benchmark directory: use its latest run.
                runs = sorted(path for path in run.iterdir() if (path / "metadata.txt").is_file())
                if not runs:
                    raise ValueError(f"No runs in {run}")
                run = runs[-1]
            result = compare_run(run)
            print(f"Wrote {result['run'] / 'comparison.md'}")
    except (OSError, ValueError, KeyError, IndexError) as error:
        sys.exit(f"Error: {error}")


if __name__ == "__main__":
    main()
