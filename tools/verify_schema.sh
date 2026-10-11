#!/usr/bin/env bash
# tools/verify_schema.sh — apply the bundled schema to a real SQLite and assert
# the facts the app depends on.
#
# Why this exists: the Dart VM in this environment cannot open an encrypted
# database (no sqflite_common_ffi in the offline cache), so the schema itself is
# verified through the `sqlite3` CLI instead. This catches the failure mode that
# would otherwise only appear at a café: a typo in the statement splitter or a
# seed row that does not apply.
#
# It checks structure, constraints and seeds — everything except encryption,
# which needs a device (test/device/README.md).
#
# Usage:  tools/verify_schema.sh [schema.sql]
set -uo pipefail

SCHEMA="${1:-assets/schema/schema.sql}"
DB="$(mktemp -d)/verify.db"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 — expected $3, got $2"; fi; }

echo "=============================================================="
echo " SCHEMA VERIFICATION — $SCHEMA"
echo "=============================================================="

if [ ! -f "$SCHEMA" ]; then
  echo "schema not found: $SCHEMA" >&2
  exit 2
fi

echo
echo "-- 1. applies cleanly --"
if sqlite3 "$DB" < "$SCHEMA" 2>/tmp/schema_err.txt; then
  ok "schema applied without error"
else
  bad "schema failed to apply: $(head -3 /tmp/schema_err.txt)"
  exit 1
fi

q() { sqlite3 "$DB" "$1"; }

echo
echo "-- 2. structure --"
check "table count" "$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")" "16"

for t in users categories products modifier_groups modifiers product_modifier_groups \
         shifts orders order_items payments inventory_items recipes stock_movements \
         backup_log settings audit_log; do
  n="$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$t';")"
  [ "$n" = "1" ] || bad "table missing: $t"
done
[ "$FAIL" = "0" ] && ok "all 16 expected tables present"

echo
echo "-- 3. seeds --"
check "categories"        "$(q 'SELECT COUNT(*) FROM categories;')"        "5"
check "products"          "$(q 'SELECT COUNT(*) FROM products;')"          "25"
check "modifier groups"   "$(q 'SELECT COUNT(*) FROM modifier_groups;')"   "6"
check "modifiers"         "$(q 'SELECT COUNT(*) FROM modifiers;')"         "20"
check "inventory items"   "$(q 'SELECT COUNT(*) FROM inventory_items;')"   "13"
check "settings"          "$(q 'SELECT COUNT(*) FROM settings;')"          "23"
check "users (seeded in code, not SQL)" "$(q 'SELECT COUNT(*) FROM users;')" "0"

echo
echo "-- 4. money and locale --"
check "first product price (minor units)" "$(q 'SELECT price_minor FROM products WHERE id=1;')" "1200"
check "currency"  "$(q "SELECT value FROM settings WHERE key='currency_code';")"  "YER"
check "tax rate"  "$(q "SELECT value FROM settings WHERE key='tax_rate';")"       "0.00"
check "tax inclusive" "$(q "SELECT value FROM settings WHERE key='tax_inclusive';")" "1"
check "theme"     "$(q "SELECT value FROM settings WHERE key='theme';")"          "dark"

echo
echo "-- 5. money column types --"
# Every money column is INTEGER minor units, EXCEPT cost_per_unit_minor, which
# is deliberately REAL: it is a cost per gram/millilitre, and rounding 1.2
# fils-per-ml to an integer would misprice every recipe. The desktop schema
# makes the same exception, so the two stay identical.
NON_INT="$(q "SELECT COUNT(*) FROM (
  SELECT m.name AS t, p.name AS c, p.type AS ty
    FROM sqlite_master m, pragma_table_info(m.name) p
   WHERE m.type='table' AND m.name NOT LIKE 'sqlite_%'
     AND p.name LIKE '%_minor' AND UPPER(p.type) <> 'INTEGER'
     AND p.name <> 'cost_per_unit_minor');")"
check "non-INTEGER *_minor columns (excluding cost_per_unit_minor)" "$NON_INT" "0"

CPU_TYPE="$(q "SELECT type FROM pragma_table_info('inventory_items') WHERE name='cost_per_unit_minor';")"
check "cost_per_unit_minor is REAL (a per-unit rate, not a total)" "$CPU_TYPE" "REAL"

MINOR_COLS="$(q "SELECT COUNT(*) FROM (
  SELECT m.name AS t, p.name AS c
    FROM sqlite_master m, pragma_table_info(m.name) p
   WHERE m.type='table' AND m.name NOT LIKE 'sqlite_%' AND p.name LIKE '%_minor');")"
check "count of *_minor columns" "$MINOR_COLS" "20"

echo
echo "-- 6. constraints --"
# PRAGMA foreign_keys is per-connection, so it has to be set in the SAME
# invocation as the insert being tested.
FK="$(sqlite3 "$DB" "PRAGMA foreign_keys=ON; INSERT INTO products (category_id,name_ar,price_minor) VALUES (99999,'x',1);" 2>&1 | grep -c "FOREIGN KEY")"
check "foreign key enforced" "$FK" "1"

q "INSERT INTO shifts (user_id,status) VALUES (1,'open');" >/dev/null 2>&1
DUP="$(sqlite3 "$DB" "INSERT INTO shifts (user_id,status) VALUES (1,'open');" 2>&1 | grep -c "UNIQUE")"
check "second open shift refused" "$DUP" "1"
CLOSED="$(sqlite3 "$DB" "INSERT INTO shifts (user_id,status) VALUES (1,'closed');" 2>&1 | grep -c "Error")"
check "closed shift allowed" "$CLOSED" "0"

echo
echo "-- 7. opening stock ledger reconciles --"
DRIFT="$(q "SELECT COUNT(*) FROM inventory_items i
   WHERE ABS(i.current_qty - (SELECT COALESCE(SUM(m.change_qty),0)
     FROM stock_movements m WHERE m.inventory_item_id = i.id)) > 0.001;")"
check "ingredients whose ledger disagrees" "$DRIFT" "0"

echo
echo "-- 8. idempotent re-apply --"
BEFORE="$(q 'SELECT COUNT(*) FROM products;')"
sqlite3 "$DB" < "$SCHEMA" >/dev/null 2>&1
AFTER="$(q 'SELECT COUNT(*) FROM products;')"
check "products unchanged after re-apply" "$AFTER" "$BEFORE"

echo
echo "=============================================================="
printf " RESULT: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "=============================================================="

rm -rf "$(dirname "$DB")"
[ "$FAIL" = "0" ] || exit 1
