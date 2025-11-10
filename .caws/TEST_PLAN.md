# CAWS Testing Plan for Deduper Project

**Date:** 2025-11-10  
**Purpose:** Verify CAWS improvements work correctly in Swift deduper project

## ✅ Pre-Test Checklist

- [x] CAWS initialized in deduper project
- [x] `.caws/working-spec.yaml` exists
- [x] `.caws/quality-exceptions.json` exists
- [x] Extension bundled with latest fixes
- [ ] Extension installed in Cursor
- [ ] Cursor restarted to load updated extension

## 🧪 Test Cases

### Test 1: Project Root Detection

**Objective:** Verify MCP server detects project root correctly

**Steps:**
1. Restart Cursor to load updated extension
2. Check if MCP server finds `.caws` directory
3. Verify `getProjectRoot()` returns deduper project root

**Expected Results:**
- ✅ MCP server detects `/Users/darianrosebrook/Desktop/Projects/deduper` as project root
- ✅ `findWorkingSpecs()` finds `.caws/working-spec.yaml`
- ✅ Not using extension directory or home directory

**How to Verify:**
- Use MCP tools (after restart) to check resources
- Check exception framework saves to project directory
- Verify commands run in project directory

### Test 2: Exception Framework Project Scoping

**Objective:** Verify exceptions save to project directory, not extension directory

**Steps:**
1. Create a test exception via MCP
2. Check where exception is saved
3. Verify it's in `.caws/quality-exceptions.json` in project root

**Expected Results:**
- ✅ Exception saved to `/Users/darianrosebrook/Desktop/Projects/deduper/.caws/quality-exceptions.json`
- ✅ NOT saved to extension directory
- ✅ Exception appears in exception list

**How to Verify:**
```bash
# Check project directory
cat /Users/darianrosebrook/Desktop/Projects/deduper/.caws/quality-exceptions.json | jq '.exceptions'

# Verify NOT in extension directory
test -f ~/.cursor/extensions/paths-design.caws-vscode-extension-5.1.0/.caws/quality-exceptions.json && echo "❌ Found in extension dir" || echo "✅ Not in extension dir"
```

### Test 3: Working Spec Discovery

**Objective:** Verify `findWorkingSpecs()` finds spec in project root

**Steps:**
1. Use MCP resource listing
2. Verify `.caws/working-spec.yaml` is found
3. Check resource URI is correct

**Expected Results:**
- ✅ Resource listed as `caws://working-spec/.caws/working-spec.yaml`
- ✅ Spec file readable from project root
- ✅ Not looking in extension directory

### Test 4: Command Execution Scoping

**Objective:** Verify commands default to project directory

**Steps:**
1. Run `caws validate` via MCP
2. Run `caws status` via MCP
3. Verify commands operate on deduper project

**Expected Results:**
- ✅ Commands find `.caws/working-spec.yaml` in project root
- ✅ Commands execute in project directory
- ✅ Output reflects deduper project state

### Test 5: Multiple Project Isolation

**Objective:** Verify multiple projects work independently

**Steps:**
1. Open another project in Cursor (if possible)
2. Verify exceptions don't conflict
3. Verify each project has its own `.caws` directory

**Expected Results:**
- ✅ Each project has isolated exceptions
- ✅ No cross-project contamination
- ✅ Project root detection works per-project

## 🔍 Verification Commands

### Check Project Root Detection

```bash
# Should return deduper project root
cd /Users/darianrosebrook/Desktop/Projects/deduper
git rev-parse --show-toplevel

# Check if .caws exists in project root
test -d .caws && echo "✅ .caws directory found" || echo "❌ .caws directory missing"
```

### Check Exception Location

```bash
# Project directory (should exist)
cat /Users/darianrosebrook/Desktop/Projects/deduper/.caws/quality-exceptions.json

# Extension directory (should NOT have project exceptions)
ls -la ~/.cursor/extensions/paths-design.caws-vscode-extension-5.1.0/.caws/quality-exceptions.json 2>&1
```

### Check Working Spec

```bash
# Should exist in project root
test -f /Users/darianrosebrook/Desktop/Projects/deduper/.caws/working-spec.yaml && echo "✅ Found" || echo "❌ Missing"
```

## 📊 Test Results Template

```
Test 1: Project Root Detection
- Status: [ ] Pass [ ] Fail
- Notes: 

Test 2: Exception Framework Project Scoping
- Status: [ ] Pass [ ] Fail
- Notes: 

Test 3: Working Spec Discovery
- Status: [ ] Pass [ ] Fail
- Notes: 

Test 4: Command Execution Scoping
- Status: [ ] Pass [ ] Fail
- Notes: 

Test 5: Multiple Project Isolation
- Status: [ ] Pass [ ] Fail [ ] Skipped
- Notes: 
```

## 🚨 Known Issues to Watch For

1. **MCP Server Not Finding Project Root**
   - Symptom: Commands fail or look in wrong directory
   - Check: Environment variables set correctly
   - Fix: Verify `CURSOR_WORKSPACE_ROOT` in MCP config

2. **Exceptions Saving to Extension Directory**
   - Symptom: Exceptions not found in project
   - Check: Exception framework using `setProjectRoot()`
   - Fix: Verify `workingDirectory` parameter passed correctly

3. **Working Spec Not Found**
   - Symptom: Resources list empty
   - Check: `findWorkingSpecs()` using `getProjectRoot()`
   - Fix: Verify project root detection works

## 📝 Post-Test Actions

After testing:
1. Document any issues found
2. Verify fixes work as expected
3. Update documentation if needed
4. Create follow-up tasks for any remaining issues



