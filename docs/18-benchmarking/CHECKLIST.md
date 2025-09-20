## 18 · Benchmarking Plan and Performance Targets — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Run harness in CI; store JSON artifacts; track regressions.

### Scope

Datasets, metrics, targets, and methodology for repeatable performance measurement.

### Acceptance Criteria

- [ ] Fixture datasets prepared (Small/Medium/Large) with counts documented.
- [ ] Metrics captured to JSON; signposts around key stages.
- [ ] Baseline targets documented and measured.
- [ ] Metrics include: time to first result, total scan time, hashes/sec (image/video), peak memory, CPU median/p95, group formation latency, UI list render latency.
- [ ] Methodology documented: fixed concurrency, cache warm/cold runs, 3 trials, median + p95.

### Verification

- [ ] Run harness produces reproducible numbers across 3 trials.

### Implementation Tasks

- [ ] CLI tool (SPM) runs scans on fixtures; writes JSON metrics.
- [ ] Instruments templates for Time Profiler and System Trace stored in repo.
- [ ] Automation script pins CPU concurrency and warms/cools caches per spec.

### Done Criteria

- Benchmarks tracked; regressions detectable; docs updated.


