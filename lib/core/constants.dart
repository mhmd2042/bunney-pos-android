/// core/constants.dart — the single source of truth for identity, money and
/// layout constants.
///
/// Ported from the desktop app's `config.py` so the two products stay the same
/// product: same name, same palette, same money base unit, same permissions.
///
/// MONEY: every amount is an INTEGER in minor units, never a double. For YER
/// (no subunit in use) a minor unit is a whole rial, so 2,500 ر.ي is `2500`.
/// Doubles are for display only and are converted at the edge.
library;

/// Application identity. The Arabic name is what the user sees; the id is what
/// Android and the data directory use, and must stay stable across releases or
/// existing installs lose their database.
class AppInfo {
  AppInfo._();

  static const String name = 'Bunney POS';
  static const String nameAr = 'نظام بُنّي للنقاط البيع';
  static const String appId = 'bunney_pos_android';
  static const String version = '1.0.0';
  static const String build = '1';
}

/// The warm coffee palette. Same values as the desktop theme so a café running
/// both sees one product.
class CoffeePalette {
  CoffeePalette._();

  // dark
  static const int darkBg = 0xFF191512;
  static const int darkSurface = 0xFF221D19;
  static const int darkSurfaceAlt = 0xFF2B2521;
  static const int darkSurfaceRaised = 0xFF332C27;
  static const int darkBorder = 0xFF3D352E;
  static const int darkBorderStrong = 0xFF4E443B;
  static const int darkText = 0xFFF6F0E7;
  static const int darkTextMuted = 0xFFB9AC9C;
  static const int darkTextDisabled = 0xFF7C7168;

  // shared accents
  static const int accent = 0xFFC98F4B;
  static const int accentHover = 0xFFDA9F5C;
  static const int accentPress = 0xFFA87334;
  static const int accentSoft = 0xFF3A2E20;
  static const int success = 0xFF6E9C6B;
  static const int danger = 0xFFC4593F;
  static const int warning = 0xFFD9A441;
  static const int info = 0xFF6C93A8;

  // light
  static const int lightBg = 0xFFF7F2EA;
  static const int lightSurface = 0xFFFFFFFF;
  static const int lightSurfaceAlt = 0xFFF1E9DD;
  static const int lightBorder = 0xFFDCCEBB;
  static const int lightText = 0xFF2A231D;
  static const int lightTextMuted = 0xFF5F5347;
}

/// Money rules.
class MoneyConfig {
  MoneyConfig._();

  /// How many minor units make one major unit. YER has no subunit in practical
  /// use, so this is 1 and an integer rial is already a minor unit.
  /// A currency with cents would set this to 100.
  static const int minorUnitsPerMajor = 1;

  static const String currencyCode = 'YER';
  static const String currencySymbol = 'ر.ي';

  /// Prices are tax-INCLUSIVE. 0% for YER, but every code path is written for
  /// any rate so an admin can raise it later without a schema change.
  static const double defaultTaxRate = 0.0;
}

/// Touch and layout sizing.
///
/// The spec asks for Android's standard 48–56dp range. 48dp is the accessibility
/// floor; 56dp is what a busy counter wants for the primary actions. Nothing in
/// the app may hardcode a width or height — these are the only numbers layouts
/// read, and every screen must still scroll rather than clip.
class Sizes {
  Sizes._();

  /// Accessibility minimum for any tappable thing.
  static const double minTouchTarget = 48.0;

  /// Primary actions on the POS (pay, checkout, keypad keys).
  static const double primaryTouchTarget = 56.0;

  /// Product tile in the grid. The tile is a grid cell, so these are hints the
  /// layout clamps, not fixed sizes.
  static const double productTileMinWidth = 120.0;
  static const double productTileMinHeight = 88.0;

  /// Below this the POS switches from a two-pane tablet layout to the phone
  /// layout with bottom navigation. 600dp is Android's own sw600dp breakpoint,
  /// the width at which the platform itself calls a device a tablet.
  static const double tabletBreakpoint = 600.0;

  /// Cards and dialogs never exceed this, so text stays readable on a 10.5"
  /// tablet instead of stretching to a 100-character line.
  static const double maxContentWidth = 720.0;

  static const double radius = 14.0;
  static const double radiusSmall = 10.0;
  static const double gap = 12.0;
  static const double gapSmall = 8.0;
  static const double pagePadding = 16.0;
}

/// Order, payment and shift literals — the same strings the schema constrains
/// to, so a value round-trips between Dart and SQLite unchanged.
class OrderType {
  OrderType._();
  static const String dineIn = 'dine_in';
  static const String takeaway = 'takeaway';
}

class OrderStatus {
  OrderStatus._();
  static const String open = 'open';
  static const String completed = 'completed';
  static const String voided = 'voided';
}

class PaymentMethod {
  PaymentMethod._();
  static const String cash = 'cash';
  static const String card = 'card';
}

class ShiftStatus {
  ShiftStatus._();
  static const String open = 'open';
  static const String closed = 'closed';
}

class BackupKind {
  BackupKind._();
  static const String auto = 'auto';
  static const String manual = 'manual';
}

class BackupStatus {
  BackupStatus._();
  static const String ok = 'ok';
  static const String failed = 'failed';
  static const String fallback = 'fallback';
}

/// Roles and capabilities — the same tree the desktop app enforces, so a café
/// that promotes a cashier gets identical behaviour on both.
class Roles {
  Roles._();
  static const String admin = 'admin';
  static const String cashier = 'cashier';
}

const Map<String, String> roleLabelsAr = {
  Roles.admin: 'المدير',
  Roles.cashier: 'الكاشير',
};

const Map<String, String> roleDescriptionsAr = {
  Roles.admin: 'كل الصلاحيات: القائمة، التقارير، المخزون، النسخ الاحتياطي',
  Roles.cashier: 'البيع فقط: إنشاء الطلبات، تحصيل الدفع، إدارة الوردية',
};

/// Capability -> the roles allowed to do it.
///
/// Views ask `user.can('edit_prices')` instead of comparing role strings, so a
/// third role later needs one entry here and nothing else.
const Map<String, Set<String>> capabilities = {
  // Selling
  'create_order': {Roles.cashier, Roles.admin},
  'take_payment': {Roles.cashier, Roles.admin},
  'apply_discount': {Roles.admin},
  'void_order': {Roles.admin},
  'open_shift': {Roles.cashier, Roles.admin},
  'close_shift': {Roles.cashier, Roles.admin},
  // Menu and pricing
  'edit_prices': {Roles.admin},
  'manage_menu': {Roles.admin},
  'manage_modifiers': {Roles.admin},
  // Insight
  'view_reports': {Roles.admin},
  'view_profit': {Roles.admin},
  'view_shift_audit': {Roles.admin},
  // Inventory
  'manage_inventory': {Roles.admin},
  // System
  'manage_backups': {Roles.admin},
  'manage_users': {Roles.admin},
  'manage_settings': {Roles.admin},
};

/// Inventory units the schema allows.
class StockUnit {
  StockUnit._();
  static const String gram = 'g';
  static const String millilitre = 'ml';
  static const String piece = 'piece';
}

const Map<String, String> stockUnitLabelsAr = {
  StockUnit.gram: 'غرام',
  StockUnit.millilitre: 'مل',
  StockUnit.piece: 'قطعة',
};

/// Stock movement reasons the schema allows.
const Map<String, String> stockReasonLabelsAr = {
  'sale': 'بيع',
  'purchase': 'توريد',
  'waste': 'هدر',
  'adjustment': 'تسوية',
  'return': 'مرتجع',
};
