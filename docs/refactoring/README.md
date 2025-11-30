# Refactoring Plan: Quick Start Guide

This directory contains a comprehensive 4-week refactoring plan for org-markdown, organized into 4 phases.

## How to Use This Plan

### 1. Start Here
Read **[00-overview.md](00-overview.md)** for:
- Executive summary of all issues found
- Phase breakdown and timeline
- Success metrics
- What we're NOT changing

### 2. Track Progress
Each phase file has a **Progress Tracking** section at the top:
- Check off items as you complete them: `- [ ]` → `- [x]`
- Add inline notes: `<!-- Note: Working on this -->`
- Record metrics: Fill in actual performance numbers
- Commit your updates regularly

**Example:**
```markdown
- [x] Bug 0.1: Sync marker validation implemented
- [x] Bug 0.1: Tests written and passing
- [ ] Bug 0.2: Refile transaction safety <!-- In progress - 80% done -->
```

### 3. Execute Sequentially
Work through phases in order:

1. **[Phase 0: Critical Bug Fixes](01-phase-0-critical.md)** (Days 1-2)
   - Fix 3 data loss bugs
   - Add tests for fixes
   - ⚠️ Must complete before other phases

2. **[Phase 1: Test Infrastructure](02-phase-1-tests.md)** (Days 3-10)
   - Build comprehensive test suites
   - Target 80%+ coverage
   - Safety net for refactoring

3. **[Phase 2: Architecture Improvements](03-phase-2-architecture.md)** (Days 11-20)
   - Deduplicate formatters
   - Optimize parser
   - Fix config merge
   - Extract datetime module

4. **[Phase 3: Sync System Hardening](04-phase-3-sync.md)** (Days 21-28)
   - Add event validation
   - Expand event model
   - Plugin state persistence
   - Complete documentation

### 4. Git Workflow
For each phase:
```bash
# Create branch
git checkout -b refactor/phase-N-name

# Make changes, track progress in phase file
git add docs/refactoring/0N-phase-N-*.md
git commit -m "Track progress on phase N"

# When complete
git add .
git commit -m "Complete Phase N: <description>"
git push origin refactor/phase-N-name

# Create PR, review, merge
```

## Quick Reference

### Current Coverage Gaps
- refile.lua: **0%** → target 90%
- sync/manager.lua: **~10%** → target 85%
- queries.lua: **0%** → target 75%
- picker.lua: **0%** → target 70%
- config.lua: **0%** → target 80%

### Critical Bugs to Fix First
1. **Sync marker data loss** - Missing END marker loses content
2. **Refile transaction** - Deletes before write completes
3. **Capture template** - Duplicate %t pattern, hardcoded name

### Key Files to Modify

**Phase 0:**
- `lua/org_markdown/sync/manager.lua`
- `lua/org_markdown/refile.lua`
- `lua/org_markdown/capture.lua`

**Phase 1:**
- `tests/test_refile_comprehensive.lua` (new)
- `tests/test_sync_comprehensive.lua` (rewrite)
- `tests/test_config_comprehensive.lua` (new)
- `tests/test_queries.lua` (new)
- `tests/test_picker.lua` (new)

**Phase 2:**
- `lua/org_markdown/agenda_formatters.lua` (new)
- `lua/org_markdown/agenda.lua`
- `lua/org_markdown/utils/parser.lua`
- `lua/org_markdown/config.lua`
- `lua/org_markdown/utils/datetime.lua` (new)

**Phase 3:**
- `lua/org_markdown/sync/manager.lua`
- `lua/org_markdown/sync/state.lua` (new)
- `lua/org_markdown/sync/PLUGIN_INTERFACE.md` (new)

## Getting Help

### If You Get Stuck
- Review the detailed implementation in each phase file
- Check code examples with line numbers
- Refer to test requirements
- Each phase has success criteria to validate

### Questions?
- Phase unclear? Check the "Goals" section
- Technical approach? See code examples in each section
- Testing? See "Test Coverage" sections
- Dependencies? Check phase header

## Progress at a Glance

Track overall completion:

- [ ] Phase 0: Critical Bug Fixes
- [ ] Phase 1: Test Infrastructure
- [ ] Phase 2: Architecture Improvements
- [ ] Phase 3: Sync System Hardening

**Started:** ___/___/___
**Target completion:** ___/___/___
**Actual completion:** ___/___/___

## Notes

Use this space to track high-level notes across phases:

```
<!-- Example:
2025-11-29: Started Phase 0, found additional edge case in sync markers
2025-12-01: Phase 0 complete, all tests passing
2025-12-02: Started Phase 1, setting up test infrastructure
-->
```

---

**Remember:** Commit progress updates to these files regularly. They serve as both a roadmap and a journal of your refactoring journey!
