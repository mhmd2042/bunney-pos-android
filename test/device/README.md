# Device-only tests

Everything under `test/` except this directory runs on the Dart VM with
`flutter test`. What lives here needs a real Android device or emulator, because
it depends on something the VM does not have:

| Test | Why it needs a device |
|---|---|
| SQLCipher encryption | `sqflite_sqlcipher` links native SQLCipher only in the Android build. On the VM there is no encrypted SQLite to open. |
| `flutter_secure_storage` | Backed by the Android Keystore, which does not exist on the VM. |
| Bluetooth / USB printing | Real hardware and real runtime permissions. |
| Font metrics and layout | The bundled Arabic font is measured by the platform text engine; the VM's font set differs, so a geometry assertion here would be measuring the wrong thing. |

## Running them

```bash
# with a device or emulator attached
flutter devices
flutter test test/device/

# or against the emulator in this project
flutter emulators --launch Pixel_Fold_API_35
flutter test test/device/
```

## Why this split exists

A test that silently passes because it never exercised the real path is worse
than no test: it reports confidence that is not there. Encryption is exactly that
case — passing `password:` to `openDatabase` proves nothing if the build linked
plain SQLite, which is why the real check reads the file's first bytes on a
device and asserts the SQLite magic is absent.

The VM-side suite (`test/domain/`, `test/data/`) covers what it can honestly
cover: the SQL schema through the `sqlite3` CLI (`tools/verify_schema.sh`), the
money rules, the permission tree and the PIN hashing.
