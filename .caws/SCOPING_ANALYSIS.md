# CAWS Project Scoping Analysis

**Date:** 2025-11-10  
**Status:** Analysis complete - Issues identified

## 🔍 Current State

### How CAWS Initializes

1. **CLI Init** (`caws init`)
   - Uses `process.cwd()` as project root
   - Creates `.caws/` directory in current directory
   - ✅ Properly scoped to project

2. **MCP Server via VS Code Extension**
   - Extension spawns MCP server with `cwd: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath`
   - ✅ Properly scoped when extension starts server

3. **MCP Server via Cursor Registration**
   - Registered in `~/.cursor/mcp.json` without `cwd` setting
   - MCP server starts with `process.cwd()` (may be extension directory or home)
   - ❌ **NOT properly scoped**

### Issues Identified

#### Issue 1: MCP Server Working Directory

**Problem:**
- When Cursor starts the MCP server, it doesn't set a working directory
- MCP server uses `process.cwd()` which may be:
  - Extension directory (`~/.cursor/extensions/...`)
  - Home directory (`~`)
  - Some other random directory

**Impact:**
- `findWorkingSpecs()` looks in wrong directory
- Commands default to wrong `workingDirectory`
- Exception framework saves to wrong location (we fixed this with `setProjectRoot()`)
- Quality gates run in wrong directory

**Location:**
```typescript
// caws/packages/caws-vscode-extension/src/extension.ts:255
mcpConfig.mcpServers.caws = {
  command: 'node',
  args: [mcpServerPath],
  env: {
    VSCODE_EXTENSION_PATH: context.extensionPath,
    VSCODE_EXTENSION_DIR: context.extensionPath,
  },
  // ❌ Missing: cwd setting
};
```

#### Issue 2: Default Working Directory

**Problem:**
- Many handlers default to `process.cwd()`:
  ```javascript
  const workingDirectory = args.workingDirectory || process.cwd();
  ```

**Impact:**
- If `workingDirectory` not provided, uses wrong directory
- Commands may operate on wrong project

**Locations:**
- `handleQualityExceptionsList` - ✅ Fixed (uses `setProjectRoot()`)
- `handleQualityExceptionsCreate` - ✅ Fixed (uses `setProjectRoot()`)
- `findWorkingSpecs()` - ❌ Still uses `process.cwd()`
- Many other handlers - ❌ Default to `process.cwd()`

#### Issue 3: Project Root Detection

**Problem:**
- `findWorkingSpecs()` uses `process.cwd()` directly:
  ```javascript
  const cawsDir = path.join(process.cwd(), '.caws');
  ```

**Impact:**
- May not find `.caws` directory if MCP server started from wrong directory
- Resources may not be listed correctly

## ✅ What We Fixed

1. **Exception Framework Root Determination**
   - Added `setProjectRoot()` function
   - Exception handlers now accept `workingDirectory` parameter
   - Exceptions saved to project directory, not extension directory

## 🔧 Recommended Fixes

### Fix 1: Detect Project Root from Git

**Approach:** Make `findWorkingSpecs()` detect git root instead of using `process.cwd()`

```javascript
findWorkingSpecs() {
  const specs = [];
  
  // Try to find git root (project root)
  let projectRoot = process.cwd();
  try {
    const gitRoot = execSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      cwd: process.cwd(),
      stdio: 'pipe'
    }).trim();
    projectRoot = gitRoot;
  } catch {
    // Not a git repo, use process.cwd()
  }
  
  const cawsDir = path.join(projectRoot, '.caws');
  const specPath = path.join(cawsDir, 'working-spec.yaml');
  
  // ... rest of function
}
```

### Fix 2: Add Workspace Detection to MCP Server

**Approach:** Detect workspace from MCP protocol context or environment

```javascript
// In MCP server initialization
function detectWorkspaceRoot() {
  // Try environment variable (if set by Cursor/VS Code)
  if (process.env.CURSOR_WORKSPACE_ROOT) {
    return process.env.CURSOR_WORKSPACE_ROOT;
  }
  if (process.env.VSCODE_WORKSPACE_ROOT) {
    return process.env.VSCODE_WORKSPACE_ROOT;
  }
  
  // Try to find git root from current directory
  try {
    return execSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: 'pipe'
    }).trim();
  } catch {
    return process.cwd();
  }
}

const WORKSPACE_ROOT = detectWorkspaceRoot();
```

### Fix 3: Update Cursor MCP Config

**Approach:** Add `cwd` to MCP server config (if Cursor supports it)

```typescript
mcpConfig.mcpServers.caws = {
  command: 'node',
  args: [mcpServerPath],
  cwd: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath, // If supported
  env: {
    VSCODE_EXTENSION_PATH: context.extensionPath,
    VSCODE_EXTENSION_DIR: context.extensionPath,
    CURSOR_WORKSPACE_ROOT: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath, // Fallback
  },
};
```

### Fix 4: Make All Handlers Git-Aware

**Approach:** Create utility function for project root detection

```javascript
function getProjectRoot(workingDirectory = process.cwd()) {
  try {
    const gitRoot = execSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      cwd: workingDirectory,
      stdio: 'pipe'
    }).trim();
    return gitRoot;
  } catch {
    return workingDirectory;
  }
}

// Use in handlers:
const projectRoot = getProjectRoot(args.workingDirectory || process.cwd());
```

## 📊 Priority

1. **High Priority:** Fix `findWorkingSpecs()` - affects resource discovery
2. **High Priority:** Add workspace detection to MCP server initialization
3. **Medium Priority:** Make handlers git-aware for better defaults
4. **Low Priority:** Update Cursor MCP config (may not be supported)

## 🧪 Testing

After fixes, verify:
1. ✅ MCP server finds `.caws` directory in project root
2. ✅ Commands default to project directory
3. ✅ Exception framework saves to project directory (already fixed)
4. ✅ Quality gates run in project directory
5. ✅ Multiple projects can run simultaneously without conflicts

## 📝 Notes

- The exception framework fix (`setProjectRoot()`) is a good pattern to follow
- Git root detection is reliable for most projects
- Environment variables provide fallback for non-git projects
- VS Code extension already handles this correctly (sets `cwd` when spawning)



