/// main.dart — application entry point.
///
/// Phase 1 boots the encrypted database, applies the schema, seeds the default
/// accounts on a fresh install and shows a foundation-status screen. The login
/// screen replaces it in phase 2, once the activation gate exists.
library;

import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'data/database.dart';
import 'data/user_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BunneyApp());
}

class BunneyApp extends StatelessWidget {
  const BunneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.nameAr,
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      // Arabic is the product's language, not a translation of one.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const BootScreen(),
    );
  }
}

/// Boots the database and reports what happened.
///
/// The database is opened here rather than lazily so a key or file problem is
/// visible immediately, with an Arabic explanation, instead of surfacing as a
/// failed query on the first sale.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String _status = 'جارٍ تهيئة قاعدة البيانات…';
  String? _error;
  bool _ready = false;
  Map<String, String> _facts = const {};

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final db = await AppDatabase.open();
      final users = UserRepository(db);

      // A fresh install has no accounts; create the documented pair and flag
      // them so the first login forces a new PIN.
      final created = await users.ensureDefaultUsers();

      final settings = await db.allSettings();
      final count = await users.count();

      if (!mounted) return;
      setState(() {
        _ready = true;
        _status = 'قاعدة البيانات جاهزة';
        _facts = {
          'المسار': db.path,
          'الحجم': '${(db.sizeBytes / 1024).toStringAsFixed(1)} KB',
          'المستخدمون': '$count',
          'أُنشئ الآن': '$created',
          'العملة': settings['currency_code'] ?? '—',
          'الضريبة': '${settings['tax_rate'] ?? '0'}%',
          'الإصدار': AppInfo.version,
        };
      });
    } on DatabaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _status = 'تعذّر فتح قاعدة البيانات';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _status = 'خطأ غير متوقع';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          // The content column is capped so a 10.5" tablet does not stretch a
          // line of text across the whole screen.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sizes.pagePadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _error == null ? Icons.local_cafe : Icons.error_outline,
                    size: 64,
                    color: _error == null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(height: Sizes.gap),
                  Text(
                    AppInfo.nameAr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  Text(
                    '${AppInfo.name} — Android ${AppInfo.version}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Sizes.gap * 2),
                  if (!_ready && _error == null)
                    const Center(child: CircularProgressIndicator()),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Sizes.pagePadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_status, style: theme.textTheme.titleMedium),
                          if (_error != null) ...[
                            const SizedBox(height: Sizes.gapSmall),
                            Text(
                              _error!,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: theme.colorScheme.error),
                            ),
                          ],
                          if (_facts.isNotEmpty) ...[
                            const SizedBox(height: Sizes.gap),
                            const Divider(),
                            const SizedBox(height: Sizes.gapSmall),
                            for (final entry in _facts.entries)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 96,
                                      child: Text(
                                        entry.key,
                                        style: theme.textTheme.labelMedium,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        entry.value,
                                        style: theme.textTheme.bodyMedium,
                                        // A path is LTR data inside an RTL
                                        // layout; without this the segments
                                        // reorder and the path reads wrong.
                                        textDirection: entry.key == 'المسار'
                                            ? TextDirection.ltr
                                            : null,
                                        textAlign: entry.key == 'المسار'
                                            ? TextAlign.left
                                            : TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_ready) ...[
                    const SizedBox(height: Sizes.gap * 2),
                    Text(
                      'المرحلة ١ مكتملة — شاشة الدخول في المرحلة ٢',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
