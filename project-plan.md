# Project Plan — EventNest Code Review & Fix

**Owner:** project-manager
**Status:** complete
**Scope:** Task 1 (Code Review) + Task 2 (Fix #1 Critical Issue) only. Task 3 is excluded.

---

## Milestones

### Milestone 1 — Planning
- **Owner:** project-manager
- **Status:** done
- [x] Read assignment file and codebase
- [x] Identify all source files, models, controllers, specs
- [x] Break Task 1 and Task 2 into granular steps
- [x] Create project-plan.md

### Milestone 2 — Code Review (Task 1)
- **Owner:** code-reviewer
- **Status:** done
- [ ] Deep review of all controllers, models, routes, config
- [ ] Identify top 7 issues prioritized by business impact
- [ ] Categorize: Security / Performance / Architecture / Data Integrity / Testing
- [ ] Write REVIEW.md with file/line references, severity, descriptions, recommended fixes
- [ ] Provide curl-based proof for at least 2 issues (requires running app)
- [ ] Create review-tasks.md with checklist

### Milestone 3 — Fix Critical Issue (Task 2)
- **Owner:** code-reviewer
- **Status:** done
- [ ] Select #1 most critical issue from REVIEW.md
- [ ] Show BEFORE proof (curl command demonstrating the bug)
- [ ] Implement minimal, production-quality fix
- [ ] Add/update tests (must fail before fix, pass after)
- [ ] Show AFTER proof (same curl command, bug is fixed)
- [ ] Commit with descriptive message

### Milestone 4 — Final Sync
- **Owner:** project-manager
- **Status:** done
- [x] Verify all tasks marked correctly
- [x] Verify REVIEW.md complete (7 issues, 2 with curl proof)
- [x] Verify fix + tests implemented (SQL injection fix + 2 new specs)
- [x] Verify proof included (before/after curl commands)
- [x] Update project-plan.md with final status

---

## Dependencies

- App must be running (docker-compose up) for curl proof
- Database must be seeded for realistic test data
- Tests must pass before and after fix

---

## Key Files

| File | Role |
|------|------|
| `app/controllers/api/v1/events_controller.rb` | Events API — contains SQL injection |
| `app/controllers/api/v1/orders_controller.rb` | Orders API — missing authorization |
| `app/controllers/api/v1/ticket_tiers_controller.rb` | Ticket tiers API — mass assignment issue |
| `app/models/ticket_tier.rb` | Ticket reservation — race condition |
| `app/models/event.rb` | Event model — callback issues |
| `config/secrets.yml` | Hardcoded secrets |
| `spec/` | Test suite |
