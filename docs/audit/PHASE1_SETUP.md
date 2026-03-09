# Phase 1 - Audit Framework Setup

This folder defines the baseline process for auditing Horizon Idle.

## 1) Severity Rubric

- `P0` - Critical
  - Data loss, corrupted save/load, progression-breaking exploit, hard lock, crash loop.
  - Target response: immediate triage and hotfix path.
- `P1` - High
  - Major gameplay regression, broken economy/combat pacing, persistent wrong state.
  - Target response: fix in current development cycle.
- `P2` - Medium
  - UX friction, inconsistent UI state, weak balancing, confusing behavior.
  - Target response: schedule after P0/P1 closure.
- `P3` - Low
  - Maintainability, style, minor polish issues.
  - Target response: opportunistic cleanup.

## 2) Evidence Standard Per Finding

Every finding must include:

1. `Finding ID` (example: `AUD-P1-012`)
2. `Severity` (`P0`..`P3`)
3. `Subsystem` (combat, save/load, economy, etc.)
4. `Location` (file path + function or scene node path)
5. `Repro Steps` (numbered, deterministic)
6. `Expected Behavior`
7. `Actual Behavior`
8. `Impact` (player-facing + technical)
9. `Likely Root Cause`
10. `Fix Direction` (minimal safe change)
11. `Owner` (person/role)
12. `Status` (`open`, `in_progress`, `blocked`, `fixed`, `verified`)
13. `Verification` (test or manual scenario that proves closure)

## 3) Audit Cadence

- Daily: update `AUDIT_LOG.md` with new findings and status changes.
- Every 2 days: reprioritize by severity and player impact.
- End of phase: publish summary counts by severity and subsystem.

## 4) Exit Criteria for Phase 1

Phase 1 is complete when:

1. Severity rubric is agreed and used consistently.
2. Findings are logged with full evidence fields.
3. Subsystem matrix coverage has assigned status for each row.
4. At least one dry-run audit entry is created and reviewed.
