## 11 · Learning & Refinement — Checklist
Author: @darianrosebrook

### For Agents

- Read `docs/agents.md`. Persist ignore pairs; keep learning opt-in and reversible.
- Never auto-delete based on learned rules.

### Scope

Feedback loop: adjust thresholds, store ignore pairs/groups, and optional user preferences.

### Acceptance Criteria

- [x] Record user feedback for duplicate detection accuracy.
- [x] Track learning metrics (false positive rate, correct detection rate).
- [x] Provide recommendations based on user feedback patterns.
- [x] Export learning data for analysis.
- [x] Reset learning data when needed.

### Verification (Automated)

- [x] Feedback records persist across app restarts.
- [x] Learning metrics update correctly based on user feedback.
- [x] Recommendations generated based on feedback patterns.

### Implementation Tasks

- [x] Resolve ambiguities (see `../ambiguities.md#11--learning--refinement`).
- [x] `FeedbackService.recordFeedback(groupId, feedbackType, confidence, notes)` records user decisions.
- [x] `FeedbackService.getRecommendations()` provides learning-based suggestions.
- [x] `FeedbackService.exportLearningData()` exports data for analysis.
- [x] `FeedbackService.resetLearningData()` clears all learning data.
- [x] Learning metrics calculation and persistence.

### Done Criteria

- Feedback respected without harming accuracy; tests green.


