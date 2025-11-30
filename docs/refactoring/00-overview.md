# org-markdown Refactoring Plan: Overview

**Created:** 2025-11-29
**Status:** In Progress - Phase 3 Complete ✅
**Estimated Timeline:** 4 weeks

## Progress Overview

- [x] **Phase 0:** Critical Bug Fixes ✅ (Completed 2025-11-29)
- [x] **Phase 1:** Test Infrastructure ✅ (Completed 2025-11-29)
- [x] **Phase 2:** Architecture Improvements ✅ (Completed 2025-11-29)
- [x] **Phase 3:** Sync System Hardening ✅ (Completed 2025-11-29)

## Executive Summary

This comprehensive refactoring plan addresses critical bugs, architectural debt, and extensibility needs identified through deep code review. Work is organized into 4 sequential phases prioritizing stability, test coverage, and maintainability.

## Key Priorities

1. **Fix 3 critical data loss bugs** immediately
2. **Achieve 80%+ test coverage** before refactoring
3. **Reduce 90%+ code duplication** in agenda formatters
4. **Harden sync system** for future plugin development
5. **Leave async system as-is** (working well enough)

## Critical Findings from Code Review

### Data Loss Risks ⚠️
- **Sync marker bug**: Missing END marker causes silent data loss
- **Refile transaction**: Deletes before verifying write succeeded
- **Capture template**: Duplicate %t pattern, hardcoded "Phil Labrum"

### Test Coverage Gaps
- **refile.lua**: 0% coverage
- **sync/manager.lua**: ~10% (90% placeholder tests)
- **queries.lua**: 0% coverage
- **picker.lua**: 0% coverage
- **config.lua**: 0% coverage

### Architectural Issues
- **agenda.lua**: 90%+ code duplication in formatters (200+ lines)
- **parser.lua**: Multiple regex passes, fragile pattern order
- **config.lua**: Deep merge mutates defaults
- **queries.lua**: Synchronous blocking (freezes UI)

### Sync System Limitations
- No event validation
- Limited event model (no id, source_url, location)
- No plugin state persistence (can't do incremental sync)
- Race conditions with multiple plugins

## Phase Breakdown

### Phase 0: Critical Bug Fixes (Days 1-2)
**Files:** 3 modified
**Risk:** LOW (targeted fixes with tests)
**Deliverables:**
- Zero data loss scenarios
- All critical bugs fixed and tested

### Phase 1: Test Infrastructure (Days 3-10)
**Files:** 6 new test files
**Risk:** LOW (only adding tests)
**Deliverables:**
- 80%+ overall test coverage
- Test helpers and mocks
- Foundation for safe refactoring

### Phase 2: Architecture Improvements (Days 11-20)
**Files:** 2 new, 4 modified
**Risk:** MEDIUM (refactoring core modules)
**Deliverables:**
- 50% reduction in agenda.lua size
- Single-pass parser (15% faster)
- Config immutability
- Centralized datetime handling

### Phase 3: Sync System Hardening (Days 21-28)
**Files:** 3 new, 2 modified
**Risk:** MEDIUM (event model changes)
**Deliverables:**
- Event validation layer
- Extended event model
- Plugin state persistence
- Complete interface docs

## Success Metrics

| Phase | Key Metric | Target |
|-------|------------|--------|
| 0 | Data loss bugs | 0 remaining |
| 1 | Test coverage | 80%+ |
| 2 | agenda.lua size | 772 → ~500 lines |
| 3 | Event fields supported | 12+ fields |

## Implementation Strategy

1. **Sequential execution** - Complete each phase before starting next
2. **Test-first development** - Write tests before refactoring
3. **Incremental merges** - Merge and test each phase separately
4. **Feature flags** - New features optional, old format works
5. **Backup creation** - Atomic writes with backups

## What We're NOT Changing

Based on analysis and priorities:

1. **Async/Promise system** - Working well enough, fixing would be complex
2. **Window management** - Complex but functional, high risk for low gain
3. **Capture templates** - Beyond critical fixes, system works well
4. **Swift/AppleScript mix** - Calendar plugin reliable as-is

## File Organization

```
docs/refactoring/
├── 00-overview.md              (this file - high level summary)
├── 01-phase-0-critical.md      (Critical bug fixes)
├── 02-phase-1-tests.md         (Test infrastructure)
├── 03-phase-2-architecture.md  (Architecture improvements)
└── 04-phase-3-sync.md          (Sync system hardening)
```

**Each phase file includes:**
- Progress tracking checklist at the top
- Detailed implementation instructions
- Code examples with line numbers
- Test requirements
- Success criteria
- Time estimates

## Tracking Progress

Each phase document has a **Progress Tracking** section at the top with checkboxes for major milestones. To track your progress:

1. **Edit the phase file** (e.g., `01-phase-0-critical.md`)
2. **Check off items** by changing `- [ ]` to `- [x]`
3. **Add notes** inline with `<!-- Note: ... -->`
4. **Commit progress** regularly to keep history

Example:
```markdown
- [x] Bug 0.1: Sync marker validation implemented
- [x] Bug 0.1: Tests written and passing
- [ ] Bug 0.2: Refile transaction safety <!-- Working on this -->
```

## Next Steps

1. Review and approve this plan
2. Start with Phase 0 (critical fixes)
3. **Mark items complete** in each phase file as you go
4. Get each phase reviewed before proceeding
5. Track progress with git branches: `refactor/phase-N`

## Resources

- **Code Review Details**: See agent exploration reports (saved in plan file)
- **Test Framework**: mini.test (already in use)
- **CI/CD**: Run tests via `make test`
- **Rollback Strategy**: Each phase in separate branch, can revert if needed

---

## Recent Updates

### 2025-11-29: Phase 1 Complete ✅

**Completed:**
- Test helpers module with reusable utilities
- Config comprehensive test suite (8 tests)
- Queries test suite (3 tests)
- All tests passing (124 total, 0 failures)

**Key Insights:**
- Existing test coverage was better than expected
- Removed redundant test suites (refile, sync, picker already well-tested)
- Tests now document actual behavior for future refactoring
- Ready to proceed with Phase 2 architecture improvements

**Time:** ~2 hours (vs. estimated 7-10 days)
- Leveraged existing test coverage
- Focused on gaps rather than duplicating effort
