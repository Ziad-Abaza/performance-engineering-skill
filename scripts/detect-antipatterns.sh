#!/usr/bin/env bash
# Performance Anti-Pattern Scanner for Laravel, Inertia & Vue 3 (Bash/POSIX)

TARGET_DIR="${1:-.}"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${CYAN}=== Scanning for Performance Anti-Patterns in: ${TARGET_DIR} ===${NC}"
echo -e "${GRAY}Searching application paths (excluding vendor, node_modules, storage, etc.)...${NC}\n"

EXCLUDE_DIRS="--exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=storage --exclude-dir=dist --exclude-dir=public --exclude-dir=bootstrap --exclude-dir=tests"

# 1. Queries inside loops
echo -e "${YELLOW}[1] Scanning for queries inside loops (foreach/while)...${NC}"
LOOP_MATCHES=$(grep -rnE $EXCLUDE_DIRS --include="*.php" -A 5 -E '(foreach|while)\s*\(.*?\)\s*\{' "$TARGET_DIR" 2>/dev/null | grep -E '::(find|where|first|create|update)\(|->(save|update|delete)\(' || true)
if [ -n "$LOOP_MATCHES" ]; then
    echo -e "${RED}${LOOP_MATCHES}${NC}"
else
    echo -e "${GRAY}  No raw loop queries detected.${NC}"
fi

# 2. Dangerous chunk() usage with updates
echo -e "\n${YELLOW}[2] Scanning for chunk() with updates (should be chunkById)...${NC}"
CHUNK_MATCHES=$(grep -rnE $EXCLUDE_DIRS --include="*.php" -A 8 '->chunk\(' "$TARGET_DIR" 2>/dev/null | grep -E '->(update|save|delete)\(' || true)
if [ -n "$CHUNK_MATCHES" ]; then
    echo -e "${RED}${CHUNK_MATCHES}${NC}"
    echo -e "${GRAY}  Replace chunk() with chunkById() to avoid index offset skips.${NC}"
else
    echo -e "${GRAY}  No dangerous chunk() updates detected.${NC}"
fi

# 3. Model $appends attributes
echo -e "\n${YELLOW}[3] Scanning for Model \$appends attributes...${NC}"
APPENDS_MATCHES=$(grep -rnE $EXCLUDE_DIRS --include="*.php" -E 'protected\s+\$appends\s*=' "$TARGET_DIR" 2>/dev/null || true)
if [ -n "$APPENDS_MATCHES" ]; then
    echo -e "${MAGENTA}${APPENDS_MATCHES}${NC}"
    echo -e "${GRAY}  Verify accessors do not query relationships or use withSum/withCount subqueries instead.${NC}"
else
    echo -e "${GRAY}  No Model \$appends detected.${NC}"
fi

# 4. Unbounded Model::all()
echo -e "\n${YELLOW}[4] Scanning for unbounded Model::all() calls...${NC}"
ALL_MATCHES=$(grep -rnE $EXCLUDE_DIRS --include="*.php" -E '[A-Z][a-zA-Z0-9_]+::all\(\)' "$TARGET_DIR" 2>/dev/null || true)
if [ -n "$ALL_MATCHES" ]; then
    echo -e "${RED}${ALL_MATCHES}${NC}"
    echo -e "${GRAY}  Use paginate() or chunkById() instead of unbounded all().${NC}"
else
    echo -e "${GRAY}  No unbounded all() detected.${NC}"
fi

# 5. Inertia.js API Anti-Patterns
echo -e "\n${YELLOW}[5] Scanning for Inertia.js API anti-patterns...${NC}"
INERTIA_ISSUES=0

# Check for chained ->group() on defer or Inertia::lazy
while IFS= read -r file; do
    if grep -qz 'Inertia::defer.*->group(' "$file" 2>/dev/null; then
        echo -e "${RED}  [!] Chained ->group() bug on defer: ${file}${NC}"
        echo -e "${GRAY}      Inertia::defer(\$fn, 'group_name') takes the group as 2nd parameter, not a chained method.${NC}"
        INERTIA_ISSUES=$((INERTIA_ISSUES + 1))
    fi
    if grep -q 'Inertia::lazy(' "$file" 2>/dev/null; then
        echo -e "${YELLOW}  [!] Inertia::lazy() detected: ${file}${NC}"
        echo -e "${GRAY}      Inertia::lazy() is removed in Inertia v3; replace with Inertia::optional().${NC}"
        INERTIA_ISSUES=$((INERTIA_ISSUES + 1))
    fi
done < <(find "$TARGET_DIR" -type f -name "*.php" ! -path "*/vendor/*" ! -path "*/storage/*" ! -path "*/tests/*" 2>/dev/null)

if [ "$INERTIA_ISSUES" -eq 0 ]; then
    echo -e "${GRAY}  No Inertia API anti-patterns detected.${NC}"
fi

# 6. PostgreSQL Concurrent Indexing in Transactions
echo -e "\n${YELLOW}[6] Scanning PostgreSQL migration safe indexing...${NC}"
PG_MIGRATION_ISSUES=0
while IFS= read -r file; do
    if grep -q 'CREATE\s\+INDEX\s\+CONCURRENTLY' "$file" 2>/dev/null; then
        if ! grep -q '\$withinTransaction\s*=\s*false' "$file" 2>/dev/null; then
            echo -e "${RED}  [!] Postgres Concurrent Index missing \$withinTransaction = false: ${file}${NC}"
            echo -e "${GRAY}      Postgres transactions block CONCURRENTLY. Add: public bool \$withinTransaction = false;${NC}"
            PG_MIGRATION_ISSUES=$((PG_MIGRATION_ISSUES + 1))
        fi
    fi
done < <(find "$TARGET_DIR" -type f -name "*.php" -path "*/migrations/*" 2>/dev/null)

if [ "$PG_MIGRATION_ISSUES" -eq 0 ]; then
    echo -e "${GRAY}  No PostgreSQL concurrent index transaction issues detected.${NC}"
fi

# 7. Vue 3 Deep Reactivity with Large Lists
echo -e "\n${YELLOW}[7] Scanning for large table reactive ref() in Vue...${NC}"
VUE_MATCHES=$(grep -rnE $EXCLUDE_DIRS --include="*.vue" --include="*.js" --include="*.ts" -E 'const\s+(rows|items|tableData|records|dataList)\s*=\s*ref\(\[\]\)' "$TARGET_DIR" 2>/dev/null || true)
if [ -n "$VUE_MATCHES" ]; then
    echo -e "${YELLOW}${VUE_MATCHES}${NC}"
    echo -e "${GRAY}  Consider shallowRef for large tables to prevent heavy reactive Proxy wrapping.${NC}"
else
    echo -e "${GRAY}  No heavy ref([]) patterns detected.${NC}"
fi

echo -e "\n${CYAN}=== Anti-Pattern Scan Complete ===${NC}"
