#!/usr/bin/env node
/**
 * performance-engineering-skill installer
 *
 * Copies the skill into a standard agent skills directory.
 *
 * Usage:
 *   npx github:Ziad-Abaza/performance-engineering-skill            # global: ~/.agents/skills
 *   npx ... --project                                             # project: <cwd>/.agents/skills
 *   npx ... --project /path/to/app                                # project: <path>/.agents/skills
 *   npx ... --claude | --devin | --cursor                          # runtime-specific target
 *   npx ... --dir /custom/path                                    # explicit target dir
 *   npx ... --force                                               # overwrite existing install
 *   npx ... --uninstall                                           # remove installed skill
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const SKILL_NAME = 'performance-engineering';
const SKILL_FILES = ['SKILL.md', 'README.md', 'LICENSE'];
const SKILL_DIRS = ['references', 'scripts', 'templates'];

const pkgRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const args = process.argv.slice(2);
const has = (flag) => args.includes(flag);
const argAfter = (flag) => {
    const i = args.indexOf(flag);
    return i !== -1 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : null;
};

function resolveTarget() {
    if (has('--claude')) return path.join(os.homedir(), '.claude', 'skills', SKILL_NAME);
    if (has('--devin')) return path.join(process.cwd(), '.devin', 'skills', SKILL_NAME);
    if (has('--cursor')) return path.join(process.cwd(), '.cursor', 'skills', SKILL_NAME);
    if (has('--project')) {
        const root = argAfter('--project') ?? process.cwd();
        return path.join(path.resolve(root), '.agents', 'skills', SKILL_NAME);
    }
    if (has('--dir')) {
        const custom = argAfter('--dir');
        if (!custom) fail('--dir requires a path argument');
        return path.resolve(custom);
    }
    // Default: cross-runtime global skills dir
    return path.join(os.homedir(), '.agents', 'skills', SKILL_NAME);
}

function fail(msg) {
    console.error(`error: ${msg}`);
    process.exit(1);
}

function copyRecursive(src, dest) {
    const stat = fs.statSync(src);
    if (stat.isDirectory()) {
        fs.mkdirSync(dest, { recursive: true });
        for (const entry of fs.readdirSync(src)) {
            copyRecursive(path.join(src, entry), path.join(dest, entry));
        }
    } else {
        fs.copyFileSync(src, dest);
    }
}

const target = resolveTarget();

if (has('--uninstall')) {
    if (fs.existsSync(target)) {
        fs.rmSync(target, { recursive: true, force: true });
        console.log(`Removed ${target}`);
    } else {
        console.log(`Nothing to remove at ${target}`);
    }
    process.exit(0);
}

if (fs.existsSync(path.join(target, 'SKILL.md')) && !has('--force')) {
    console.log(`Skill already installed at ${target}`);
    console.log('Re-run with --force to overwrite.');
    process.exit(0);
}

for (const f of [...SKILL_FILES, ...SKILL_DIRS]) {
    if (!fs.existsSync(path.join(pkgRoot, f))) fail(`missing ${f} in package — corrupted install`);
}

fs.mkdirSync(target, { recursive: true });
for (const f of SKILL_FILES) copyRecursive(path.join(pkgRoot, f), path.join(target, f));
for (const d of SKILL_DIRS) copyRecursive(path.join(pkgRoot, d), path.join(target, d));

console.log(`\nperformance-engineering skill installed to:\n  ${target}`);
console.log('\nRestart your agent session, then try: "Audit this page for performance issues."');
