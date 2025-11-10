# CAWS Setup Review - What We Have vs What We Need

**Date:** 2025-11-10  
**Reviewer:** CAWS Audit  
**Status:** Ready to configure

## Summary

CAWS is initialized in the deduper project, but some configuration is needed to enable full functionality. The CAWS project source is now available in the workspace, giving us access to all tools and frameworks.

## What's Available from CAWS Project

### ✅ Exception Framework
- **Location:** `caws/packages/quality-gates/shared-exception-framework.mjs`
- **Status:** Available and functional
- **Purpose:** Manages quality gate exceptions and waivers
- **Issue:** MCP server path resolution needs fixing for VS Code extension

### ✅ Code Freeze Gate
- **Location:** `caws/packages/quality-gates/check-code-freeze.mjs`
- **Status:** Active and blocking "feat" commits
- **Configuration Options:**
  1. Disable via `.caws/code-freeze.yaml`
  2. Disable via `.caws/quality-exceptions.json` global override
  3. Create exception for specific violations

### ✅ Quality Gates System
- **Location:** `caws/packages/quality-gates/`
- **Available Gates:**
  - Code freeze (`check-code-freeze.mjs`)
  - Naming conventions (`check-naming.mjs`)
  - Duplication (`check-duplication.mjs`)
  - Functional duplication (`check-functional-duplication.mjs`)
  - God objects (`check-god-objects.mjs`)
  - Documentation quality (`doc-quality-linter.mjs`)
  - Hidden TODOs (`todo-analyzer.mjs`)

## What Needs Configuration

### 1. Code Freeze Configuration (IMMEDIATE)

**Option A: Disable Code Freeze (Recommended for Development)**

Create `.caws/code-freeze.yaml`:
```yaml
# Disable code freeze for active development
enabled: false
```

**Option B: Configure Code Freeze with Exceptions**

Create `.caws/quality-exceptions.json`:
```json
{
  "schema_version": "2.0.0",
  "description": "Quality gate exceptions for deduper project",
  "global_overrides": {
    "code_freeze": {
      "enabled": false
    }
  },
  "gates": {},
  "exceptions": []
}
```

**Option C: Create Exception for Feature Commits**

Use the exception framework to allow "feat" commits with proper justification.

### 2. Exception Framework Path Resolution

**Issue:** MCP server can't find exception framework module  
**Location:** `caws/packages/caws-mcp-server/index.js` (lines 1444-1454)  
**Fix Needed:** Update import path resolution for VS Code extension context

**Current Code:**
```javascript
const { addException } = await import(
  path.join(
    path.dirname(path.dirname(__filename)),
    '..',
    '..',
    'packages',
    'quality-gates',
    'shared-exception-framework.mjs'
  )
);
```

**Solution:** Make path resolution work in both development and bundled contexts.

### 3. Git Hooks Installation

**Status:** Not installed  
**Command:** `caws hooks install`  
**Impact:** Automatic provenance tracking on commits  
**Priority:** Low (can be done manually)

### 4. CAWS Tools Directory

**Status:** Missing  
**Command:** `caws scaffold`  
**Impact:** Limited scaffolding features  
**Priority:** Low (optional)

## Recommended Actions

### Immediate (Fix Code Freeze)

1. **Create `.caws/code-freeze.yaml`** to disable code freeze for development:
```yaml
enabled: false
```

OR

2. **Create `.caws/quality-exceptions.json`** with global override:
```json
{
  "schema_version": "2.0.0",
  "global_overrides": {
    "code_freeze": {
      "enabled": false
    }
  },
  "gates": {},
  "exceptions": []
}
```

### Short-term (Improve Integration)

1. **Fix MCP Server Path Resolution**
   - Update `caws/packages/caws-mcp-server/index.js` to handle both dev and bundled contexts
   - Test exception creation via MCP server

2. **Install Git Hooks**
   - Run `caws hooks install` in deduper project
   - Verify provenance tracking works

3. **Test Exception Framework**
   - Create test exception via CLI or MCP
   - Verify it works with quality gates

### Medium-term (Enhancement)

1. **Bundle Exception Framework in VS Code Extension**
   - Include `shared-exception-framework.mjs` in extension bundle
   - Update import paths to use bundled version

2. **Create Quality Gate Configuration**
   - Set up `.caws/quality-exceptions.json` with project-specific rules
   - Configure enforcement levels per context (commit/push/ci)

3. **Document Project-Specific CAWS Configuration**
   - Document which gates are active
   - Document exception policies
   - Document enforcement levels

## Code Freeze Gate Details

### Current Behavior
- **Blocks:** "feat" and "perf" commit types
- **Allows:** "fix", "refactor", "chore", "docs", "test", "revert"
- **Enforcement:** Block level (prevents commits)
- **Config File:** `.caws/code-freeze.yaml` (doesn't exist yet, using defaults)

### Configuration Options

**Disable Entirely:**
```yaml
# .caws/code-freeze.yaml
enabled: false
```

**Customize Blocked Types:**
```yaml
# .caws/code-freeze.yaml
blocked_commit_types: ['feat']  # Only block 'feat', allow 'perf'
allowed_commit_types: ['fix', 'refactor', 'chore', 'docs', 'test', 'revert']
```

**Adjust Budgets:**
```yaml
# .caws/code-freeze.yaml
max_total_insertions: 1000  # Increase from default 500
max_per_file_insertions: 500  # Increase from default 300
```

**Allow New Files:**
```yaml
# .caws/code-freeze.yaml
allowed_new_file_patterns:
  - '**/*.md'
  - '**/*.test.*'
  - '**/Sources/**/*.swift'  # Allow Swift source files
```

## Exception Framework Usage

### Create Exception via CLI (When Fixed)

```bash
# Create exception for code freeze gate
node caws/packages/quality-gates/shared-exception-framework.mjs add \
  --gate code_freeze \
  --reason "Active development - code freeze not applicable" \
  --approved-by "darianrosebrook" \
  --expires-at "2026-12-31T23:59:59Z" \
  --context all
```

### Create Exception via Code

```javascript
import { addException } from './shared-exception-framework.mjs';

const result = await addException('code_freeze', {
  reason: 'Active development - code freeze not applicable',
  approvedBy: 'darianrosebrook',
  expiresAt: '2026-12-31T23:59:59Z',
  context: 'all',
  violationType: 'new_feature_commit'
});
```

## Next Steps

1. ✅ **Create code freeze configuration** (disable for development)
2. ⚠️ **Fix MCP server path resolution** (for exception framework)
3. ⚠️ **Test exception creation** (verify it works)
4. ⚠️ **Install git hooks** (optional, for automatic tracking)
5. ⚠️ **Document project CAWS configuration** (for team reference)

## Files to Create/Update

### Create These Files:

1. **`.caws/code-freeze.yaml`** - Disable code freeze for development
2. **`.caws/quality-exceptions.json`** - Quality gate exceptions configuration

### Update These Files:

1. **`caws/packages/caws-mcp-server/index.js`** - Fix exception framework import path
2. **`caws/packages/caws-vscode-extension/`** - Bundle exception framework or fix paths

## Testing Checklist

- [ ] Code freeze disabled - "feat" commits allowed
- [ ] Exception framework accessible via MCP server
- [ ] Exception creation works via CLI
- [ ] Exception creation works via MCP server
- [ ] Quality gates respect exceptions
- [ ] Git hooks installed (if desired)
- [ ] Provenance tracking works (if hooks installed)




