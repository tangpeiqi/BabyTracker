## Title
Baby Activity Tracker (Ray-Ban Meta Gen 2 + iPhone): Finalized Plan v3 (Persist `other`)

## Summary
Updated per your requirement: `other` is now persisted in logs (not discarded), shown inline in timeline, and can be edited or deleted later.

## Key Change From v2
- Previous rule: discard `other`.
- New rule: save `other` as first-class timeline event with badge + edit/delete actions.

## Stage 1 Decision Logic (Updated)
- Trigger: automatic classification on ingest.
- Video: upload full short clip.
- If label is tracked (`diaper_wet`, `diaper_bowel`, `feeding`, `sleep_start`, `wake_up`):
  - Save event immediately.
  - Flag `needsReview` when confidence is below threshold.
- If label is `other`:
  - Save event immediately as `other`.
  - Show inline in timeline with `Other` badge.
  - Allow user edit to a tracked label or delete entirely.

## Interfaces / Types (Updated)
- `enum ActivityLabel { diaperWet, diaperBowel, feeding, sleepStart, wakeUp, other }`
- `struct ActivityEvent { id, label, timestamp, snapshotURL?, sourceCaptureId, confidence, needsReview, isUserCorrected, isDeleted }`

## UI Flows (Updated)
- `Timeline`:
  - Shows all labels including `other`.
  - `other` rows include badge and quick actions:
    - `Re-label`
    - `Delete`
- `Capture`:
  - `other` items show status `saved_other` instead of discarded.

## Test Cases (Updated)
- Unit:
  - `other` persistence and retrieval.
  - re-label `other` -> tracked label.
  - delete `other` event behavior.
- Manual E2E:
  - Create at least one `other` event and verify it appears in timeline.
  - Re-label one `other` to tracked activity and verify update.
  - Delete one `other` and verify it no longer appears.

## Acceptance Criteria (Updated)
- Real-device E2E works from capture -> classification -> persistence.
- All 4 tracked activities can be logged from real captures.
- `other` events are persisted, visible inline, editable, and deletable.
- Saved events include timestamp and preview/snapshot (or defined placeholder).
- Low-confidence events are flagged for review.

## Assumptions / Defaults
- DAT exact API calls still placeholder-wrapped until docs are accessible in this environment.
- Gemini free tier used for Stage 1 prototype.
- API key in debug client config for Stage 1 only.
