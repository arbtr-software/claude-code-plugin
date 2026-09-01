#!/usr/bin/env node
/**
 * Import Detection Helper
 *
 * Detects new external dependencies in source files and logs them to Arbtr.
 * Used by the PostToolUse hook for automatic choice logging.
 *
 * Usage:
 *   node detect-imports.mjs <file_path> <content> <api_url> <api_key>
 *
 * This script:
 * 1. Parses the file content for imports
 * 2. Filters out relative and built-in imports
 * 3. Checks against package.json (if available)
 * 4. Logs new dependencies to Arbtr via /api/cli/log
 *
 * Exit codes:
 *   0 - Success (logged or nothing to log)
 *   1 - Error (missing args, parse failure, etc.)
 */

import fs from "fs";
import path from "path";

// ===========================================================================
// CONFIGURATION
// ===========================================================================

const SUPPORTED_EXTENSIONS = new Set([
  ".js",
  ".jsx",
  ".ts",
  ".tsx",
  ".mjs",
  ".cjs",
  ".mts",
  ".cts",
]);

// Built-in Node.js modules to ignore
const NODE_BUILTINS = new Set([
  "fs",
  "path",
  "http",
  "https",
  "crypto",
  "util",
  "os",
  "stream",
  "events",
  "buffer",
  "child_process",
  "cluster",
  "net",
  "dns",
  "url",
  "querystring",
  "readline",
  "zlib",
  "assert",
  "tty",
  "vm",
  "v8",
  "process",
  "module",
  "worker_threads",
  "perf_hooks",
  "async_hooks",
  "timers",
  "constants",
  "dgram",
  "domain",
  "punycode",
  "repl",
  "string_decoder",
]);

// ===========================================================================
// IMPORT PARSING
// ===========================================================================

/**
 * Parse imports from JavaScript/TypeScript code
 * @param {string} code - Source code content
 * @returns {string[]} - Array of external package names
 */
function parseImports(code) {
  const imports = new Set();

  // ES6 imports: import X from 'package' or import { X } from 'package'
  const es6Pattern =
    /import\s+(?:(?:\{[^}]*\}|\*\s+as\s+\w+|\w+)\s*,?\s*)*\s*from\s*['"]([^'"]+)['"]/g;
  let match;
  while ((match = es6Pattern.exec(code)) !== null) {
    imports.add(match[1]);
  }

  // ES6 side-effect imports: import 'package'
  const sideEffectPattern = /import\s*['"]([^'"]+)['"]/g;
  while ((match = sideEffectPattern.exec(code)) !== null) {
    imports.add(match[1]);
  }

  // CommonJS requires: require('package')
  const requirePattern = /require\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
  while ((match = requirePattern.exec(code)) !== null) {
    imports.add(match[1]);
  }

  // Dynamic imports: import('package')
  const dynamicPattern = /import\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
  while ((match = dynamicPattern.exec(code)) !== null) {
    imports.add(match[1]);
  }

  return Array.from(imports);
}

/**
 * Extract the root package name from an import path
 * @param {string} importPath - Full import path (e.g., 'lodash/debounce')
 * @returns {string} - Root package name (e.g., 'lodash')
 */
function getRootPackage(importPath) {
  // Handle scoped packages (@org/package)
  if (importPath.startsWith("@")) {
    const parts = importPath.split("/");
    if (parts.length >= 2) {
      return `${parts[0]}/${parts[1]}`;
    }
  }
  // Handle regular packages with subpaths
  return importPath.split("/")[0];
}

/**
 * Check if an import is relative (./xxx, ../xxx, /xxx)
 * @param {string} importPath - Import path
 * @returns {boolean}
 */
function isRelativeImport(importPath) {
  return (
    importPath.startsWith("./") ||
    importPath.startsWith("../") ||
    importPath.startsWith("/") ||
    importPath.startsWith("@/") // Common Next.js/TS path alias
  );
}

/**
 * Check if a package is a Node.js built-in
 * @param {string} packageName - Package name
 * @returns {boolean}
 */
function isBuiltinModule(packageName) {
  const rootPkg = getRootPackage(packageName);
  // Also check for node: prefix (e.g., node:fs)
  if (rootPkg.startsWith("node:")) {
    return true;
  }
  return NODE_BUILTINS.has(rootPkg);
}

/**
 * Filter imports to only external packages
 * @param {string[]} imports - Raw import paths
 * @returns {string[]} - Deduplicated external root packages
 */
function filterExternalPackages(imports) {
  const external = new Set();

  for (const imp of imports) {
    // Skip relative imports
    if (isRelativeImport(imp)) continue;

    // Skip built-in modules
    if (isBuiltinModule(imp)) continue;

    // Get root package and add to set
    const rootPkg = getRootPackage(imp);
    external.add(rootPkg);
  }

  return Array.from(external);
}

// ===========================================================================
// PACKAGE.JSON CHECKING
// ===========================================================================

/**
 * Find and parse the nearest package.json
 * @param {string} filePath - Path to the source file
 * @returns {Object|null} - Parsed package.json or null
 */
function findPackageJson(filePath) {
  let dir = path.dirname(path.resolve(filePath));

  while (dir !== path.parse(dir).root) {
    const pkgPath = path.join(dir, "package.json");
    if (fs.existsSync(pkgPath)) {
      try {
        const content = fs.readFileSync(pkgPath, "utf-8");
        return {
          data: JSON.parse(content),
          path: pkgPath,
        };
      } catch {
        return null;
      }
    }
    dir = path.dirname(dir);
  }

  return null;
}

/**
 * Get all packages declared in package.json
 * @param {Object} pkg - Parsed package.json
 * @returns {Set<string>} - Set of package names
 */
function getDeclaredPackages(pkg) {
  const packages = new Set();

  const sections = [
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
  ];

  for (const section of sections) {
    if (pkg[section]) {
      for (const name of Object.keys(pkg[section])) {
        packages.add(name);
      }
    }
  }

  return packages;
}

// ===========================================================================
// ARBTR API
// ===========================================================================

/**
 * Log a new dependency to Arbtr
 * @param {string} apiUrl - API base URL
 * @param {string} apiKey - API key for authentication
 * @param {string} packageName - Package being logged
 * @param {string} filePath - File where the package is imported
 * @returns {Promise<boolean>} - Success status
 */
async function logNewDependency(apiUrl, apiKey, packageName, filePath) {
  try {
    const response = await fetch(`${apiUrl}/log`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        choice_type: "dependency",
        description: `Added ${packageName} package`,
        key: packageName,
        category: "dependencies",
        evidence: { file_path: filePath },
      }),
      signal: AbortSignal.timeout(5000), // 5 second timeout
    });

    if (!response.ok) {
      console.error(`Failed to log ${packageName}: ${response.status}`);
      return false;
    }

    const data = await response.json();

    // Log related decisions if any
    if (data.related_decisions && data.related_decisions.length > 0) {
      console.log(`\nLogged: ${packageName}`);
      console.log("Related decisions:");
      for (const decision of data.related_decisions) {
        console.log(
          `  - ${decision.title} (${Math.round(decision.similarity * 100)}%)`,
        );
      }
    }

    return true;
  } catch (error) {
    // Fire-and-forget - don't fail the hook on API errors
    console.error(`Error logging ${packageName}:`, error.message);
    return false;
  }
}

// ===========================================================================
// MAIN
// ===========================================================================

async function main() {
  const [, , filePath, content, apiUrl, apiKey] = process.argv;

  // Validate arguments
  if (!filePath || !content || !apiUrl || !apiKey) {
    console.error(
      "Usage: node detect-imports.mjs <file_path> <content> <api_url> <api_key>",
    );
    process.exit(1);
  }

  // Check if file type is supported
  const ext = path.extname(filePath).toLowerCase();
  if (!SUPPORTED_EXTENSIONS.has(ext)) {
    // Not a supported file type - exit silently
    process.exit(0);
  }

  // Parse imports from the content
  const rawImports = parseImports(content);
  if (rawImports.length === 0) {
    // No imports found
    process.exit(0);
  }

  // Filter to external packages only
  const externalPackages = filterExternalPackages(rawImports);
  if (externalPackages.length === 0) {
    // No external packages
    process.exit(0);
  }

  // Find package.json to check for new vs existing packages
  const pkgJson = findPackageJson(filePath);
  const declaredPackages = pkgJson
    ? getDeclaredPackages(pkgJson.data)
    : new Set();

  // Find new packages not in package.json
  const newPackages = externalPackages.filter(
    (pkg) => !declaredPackages.has(pkg),
  );

  if (newPackages.length === 0) {
    // All packages are already declared
    process.exit(0);
  }

  // Log each new package to Arbtr
  for (const pkg of newPackages) {
    await logNewDependency(apiUrl, apiKey, pkg, filePath);
  }

  process.exit(0);
}

main().catch((error) => {
  console.error("Unexpected error:", error);
  process.exit(1);
});
