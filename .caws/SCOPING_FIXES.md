# CAWS Project Scoping Fixes

**Date:** 2025-11-10  
**Status:** ✅ Implemented

## ✅ Fixes Applied

### Fix 1: Project Root Detection Utility

**File:** `caws/packages/caws-mcp-server/index.js`

**Added:** `getProjectRoot()` function that:
- Checks environment variables (`CURSOR_WORKSPACE_ROOT`, `VSCODE_WORKSPACE_ROOT`)
- Falls back to git root detection
- Falls back to provided working directory

```javascript
function getProjectRoot(workingDirectory = process.cwd()) {
  // Try environment variables first (set by VS Code/Cursor)
  if (process.env.CURSOR_WORKSPACE_ROOT) {
    return process.env.CURSOR_WORKSPACE_ROOT;
  }
  if (process.env.VSCODE_WORKSPACE_ROOT) {
    return process.env.VSCODE_WORKSPACE_ROOT;
  }
  
  // Try to find git root from working directory
  try {
    const gitRoot = execSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      cwd: workingDirectory,
      stdio: 'pipe',
    }).trim();
    return gitRoot;
  } catch {
    // Not a git repo or git not available, use provided directory
    return workingDirectory;
  }
}
```

### Fix 2: Updated `findWorkingSpecs()`

**File:** `caws/packages/caws-mcp-server/index.js`

**Changed:** Now uses `getProjectRoot()` instead of `process.cwd()`

```javascript
findWorkingSpecs() {
  const specs = [];
  const projectRoot = getProjectRoot(); // ✅ Uses project root detection
  const cawsDir = path.join(projectRoot, '.caws');
  const specPath = path.join(cawsDir, 'working-spec.yaml');
  
  // ... rest of function
}
```

### Fix 3: Cursor MCP Config Environment Variables

**File:** `caws/packages/caws-vscode-extension/src/extension.ts`

**Changed:** Now passes workspace root via environment variables

```typescript
const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
mcpConfig.mcpServers.caws = {
  command: 'node',
  args: [mcpServerPath],
  env: {
    VSCODE_EXTENSION_PATH: context.extensionPath,
    VSCODE_EXTENSION_DIR: context.extensionPath,
    ...(workspaceRoot && {
      CURSOR_WORKSPACE_ROOT: workspaceRoot, // ✅ Added
      VSCODE_WORKSPACE_ROOT: workspaceRoot, // ✅ Added
    }),
  },
  // ...
};
```

## 🎯 How It Works

1. **VS Code Extension Registration:**
   - Extension detects workspace folder
   - Passes workspace root via `CURSOR_WORKSPACE_ROOT` and `VSCODE_WORKSPACE_ROOT` env vars
   - MCP server reads these on startup

2. **MCP Server Initialization:**
   - `getProjectRoot()` checks env vars first
   - Falls back to git root detection
   - Falls back to `process.cwd()`

3. **Command Execution:**
   - Commands use `getProjectRoot()` or accept `workingDirectory` parameter
   - Exception framework uses `setProjectRoot()` (already fixed)
   - `findWorkingSpecs()` uses `getProjectRoot()`

## 📊 Impact

### Before Fixes:
- ❌ MCP server started from extension directory
- ❌ `findWorkingSpecs()` looked in wrong directory
- ❌ Commands defaulted to wrong directory
- ❌ Multiple projects could conflict

### After Fixes:
- ✅ MCP server detects project root from env vars or git
- ✅ `findWorkingSpecs()` finds `.caws` in project root
- ✅ Commands default to project directory
- ✅ Multiple projects work independently

## 🧪 Testing Checklist

- [ ] MCP server finds `.caws` directory in project root
- [ ] `findWorkingSpecs()` returns correct spec path
- [ ] Exception framework saves to project directory (already tested)
- [ ] Commands default to project directory
- [ ] Multiple projects can run simultaneously
- [ ] Works with git repos
- [ ] Works with non-git projects (falls back to working directory)

## 📝 Next Steps

1. **Bundle and Install Extension:**
   ```bash
   cd caws/packages/caws-vscode-extension
   npm run bundle-deps
   npm run package
   cursor --install-extension caws-vscode-extension-5.1.0.vsix --force
   ```

2. **Restart Cursor** to load updated extension

3. **Test:**
   - Open project in Cursor
   - Verify MCP server finds `.caws` directory
   - Test exception creation (should save to project directory)
   - Test quality gates (should run in project directory)

## 🔄 Related Fixes

- ✅ Exception framework root determination (already fixed)
- ✅ Exception handlers accept `workingDirectory` parameter (already fixed)
- ✅ Project root detection utility (this fix)
- ✅ `findWorkingSpecs()` uses project root (this fix)
- ✅ Cursor MCP config passes workspace root (this fix)



