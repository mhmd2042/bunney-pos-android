# Bunney POS — Android

نظام بُنّي للنقاط البيع — تطبيق أندرويد محلي بالكامل للهواتف والأجهزة اللوحية.

A local, offline point-of-sale for a small café. Flutter + SQLite, no internet,
no server, no telemetry. It is the Android companion to the desktop app
(`cafe-pos`) and shares its database schema, its colour palette, its money rules
and its permission tree — but it is a **separate repository** with its own build,
so the two never interfere.

---

## What works today

**Phase 1 — foundation (done).** The schema, the money rules and the permission
tree are in place and verified.

| Area | State |
|---|---|
| 16-table SQLite schema, same as desktop | ✅ verified against real SQLite |
| Money as integer minor units (YER, 0% VAT) | ✅ 25 tests |
| Two-role permission tree (18 capabilities) | ✅ |
| PIN hashing (salted, iterated HMAC-SHA256) | ✅ SHA-256 proven against reference vectors |
| Encrypted database (SQLCipher) | ⚙️ wired, device test pending |
| Coffee-palette theme, Arabic font bundled | ✅ |
| Responsive layout (phone / tablet) | ✅ overflow-tested at 6 sizes |
| Debug APK builds | ✅ verified with `aapt2 dump badging` |
| Activation gate | ⏳ phase 2 |
| POS, shifts, admin, printing | ⏳ phases 3–7 |

---

## Running the checks

```bash
./tools/verify.sh
```

That runs three gates: the SQL schema against a real SQLite, `flutter analyze`,
and the Dart test suite. **A phase is not done until this is green.**

Current: **69 checks passing** (23 schema + 46 Dart), zero analyzer issues.

### What needs a device

The database is encrypted with SQLCipher, which is only linked in the Android
build. A plain Dart VM cannot open an encrypted file, so that check runs on a
device:

```bash
flutter test test/device/            # on a connected device or emulator
```

---

## Project layout

```
lib/
├── core/            constants, money rules, theme
├── domain/          pure Dart: users, permissions, PIN hashing
├── data/            database + repositories (SQLite, SQLCipher)
└── features/        screens (added per phase)
```

**Layer rule:** `domain/` and `data/` import nothing from Flutter's widget
layer. That is what lets money, permissions and the shift state machine be tested
with `flutter test` and no emulator — the same discipline the desktop app uses.

---

## Seeded accounts

A fresh install creates two accounts, both flagged to force a PIN change on
first login:

| User | PIN | Role |
|---|---|---|
| `admin` | `1234` | المدير — full access |
| `cashier` | `1111` | الكاشير — sell, take payment, manage the shift |

**Change them on first login.** They are documented here so a café operator can
get in; they are not a security measure.

---

## Money rules

Every amount is an **integer in minor units** — never a double. For YER, which
has no subunit in practical use, a minor unit is a whole rial, so 2,500 ر.ي is
`2500`. Prices are tax-inclusive; at the default 0% rate no tax is extracted,
but every code path is written for any rate so raising it later needs no schema
change.

## Data safety

The database file is encrypted with SQLCipher. The 256-bit key is generated on
first run and kept in the **Android Keystore** through `flutter_secure_storage`
— never in the database, never in the source, never in a log. Losing the Keystore
entry (an app reinstall, "clear data") means the database cannot be opened; the
backup export is the supported way to move data between devices.

---

## Licence

MIT — see `LICENSE`.
