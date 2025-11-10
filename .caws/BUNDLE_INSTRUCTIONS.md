# Extension Bundling Instructions

**Date:** 2025-11-10  
**Purpose:** Manual bundling steps if automated process encounters issues

## Quick Bundle Command

```bash
cd /Users/darianrosebrook/Desktop/Projects/caws/packages/caws-vscode-extension

# Step 1: Copy updated MCP server
cp ../caws-mcp-server/index.js bundled/mcp-server/index.js

# Step 2: Bundle dependencies (if needed)
npm run bundle-deps

# Step 3: Package extension
npm run package

# Step 4: Install into Cursor
cursor --install-extension caws-vscode-extension-5.1.0.vsix --force
```

## Verification Steps

### 1. Verify Source File Has Improvements

```bash
cd /Users/darianrosebrook/Desktop/Projects/caws/packages/caws-mcp-server
grep -c "Provide helpful error message" index.js
# Should return: 3
```

### 2. Verify Bundled File Updated

```bash
cd /Users/darianrosebrook/Desktop/Projects/caws/packages/caws-vscode-extension
grep -c "Provide helpful error message" bundled/mcp-server/index.js
# Should return: 3 (after copying)
```

### 3. Verify Extension Installed

```bash
cursor --list-extensions | grep caws
# Should show: paths-design.caws-vscode-extension
```

## Troubleshooting

### If bundling fails:

1. **Check Node version:**
   ```bash
   node --version  # Should be >= 18.0.0
   ```

2. **Check npm:**
   ```bash
   npm --version  # Should be >= 10.0.0
   ```

3. **Clean and retry:**
   ```bash
   cd /Users/darianrosebrook/Desktop/Projects/caws/packages/caws-vscode-extension
   rm -rf bundled
   npm run bundle-deps
   ```

### If installation fails:

1. **Check Cursor path:**
   ```bash
   which cursor
   # Should show: /usr/local/bin/cursor
   ```

2. **Try with full path:**
   ```bash
   /usr/local/bin/cursor --install-extension caws-vscode-extension-5.1.0.vsix --force
   ```

3. **Check extension directory:**
   ```bash
   ls -la ~/.cursor/extensions/ | grep caws
   ```

## After Installation

1. **Restart Cursor** - Required for changes to take effect
2. **Test Exception Framework:**
   - Use MCP tools in Cursor
   - Verify error messages are helpful
   - Test exception creation

## Expected Results

After successful bundling and installation:

- ✅ Extension version 5.1.0 installed
- ✅ MCP server has improved error messages
- ✅ Graceful degradation working
- ✅ Path resolution optimized
- ✅ Exception framework accessible

