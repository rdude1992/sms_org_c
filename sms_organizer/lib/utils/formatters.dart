import 'package:intl/intl.dart';

class Formatters {
  static final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _currencyPrecise =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _dayOnly = DateFormat('d');
  static final _dayMonth = DateFormat('d MMM');
  static final _dayMonthYearShort = DateFormat('d MMM yy');
  static final _dayMonthYear = DateFormat('d MMM yyyy');
  static final _timeOfDay = DateFormat('h:mm a');
  static final _fullDate = DateFormat('d MMM yyyy, h:mm a');
  static final _monthYear = DateFormat('MMM yyyy');
  static final _monthOnly = DateFormat('MMM');
  static final _yearOnlyShort = DateFormat('yy');

  static String currency(double value) => _currency.format(value);
  static String currencyPrecise(double value) => _currencyPrecise.format(value);
  static String monthYear(DateTime date) => _monthYear.format(date);
  /// e.g. "Aug 25" — TrendBarChart's x-axis tick labels, where the full
  /// 4-digit year (see [monthYear], still used for drilldown titles/
  /// tooltips where there's room) pushed the first/last tick past the
  /// chart's edge on a wide date range like "All time".
  /// Month and short-year split apart — TrendBarChart's x-axis stacks these
  /// on two lines instead of "MMM yy" on one, so adjacent tick labels on a
  /// wide "All time" range don't run into each other horizontally.
  static String monthOnly(DateTime date) => _monthOnly.format(date);
  static String yearOnlyShort(DateTime date) => _yearOnlyShort.format(date);
  static String dayOnly(DateTime date) => _dayOnly.format(date);
  static String dayMonth(DateTime date) => _dayMonth.format(date);
  static String dayMonthYear(DateTime date) => _dayMonthYear.format(date);
  static String timeOfDay(DateTime date) => _timeOfDay.format(date);

  /// Short Indian-convention form (₹90K / ₹4.2L / ₹1.1Cr) for spots too
  /// narrow for the full [currency] format — e.g. TrendBarChart's y-axis
  /// labels, where "₹88,979" would either overlap the next tick or force
  /// the reserved axis width absurdly wide.
  static String compactCurrency(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 10000000) return '$sign₹${(abs / 10000000).toStringAsFixed(abs >= 100000000 ? 0 : 1)}Cr';
    if (abs >= 100000) return '$sign₹${(abs / 100000).toStringAsFixed(abs >= 1000000 ? 0 : 1)}L';
    if (abs >= 1000) return '$sign₹${(abs / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}K';
    return '$sign₹${abs.toStringAsFixed(0)}';
  }

  /// [includeYear] switches the non-today/non-yesterday fallback from
  /// "d MMM" to "d MMM yy" — used by transaction list items, where a bare
  /// "10 Dec" is ambiguous once the list spans more than one year.
  static String relativeOrTime(DateTime date, {bool includeYear = false}) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return _timeOfDay.format(date);
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day;
    if (isYesterday) return 'Yesterday';
    return includeYear ? _dayMonthYearShort.format(date) : _dayMonth.format(date);
  }

  static String full(DateTime date) => _fullDate.format(date);

  static String dateLabel(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day;
    if (isYesterday) return 'Yesterday';
    if (date.year == now.year) return _dayMonth.format(date);
    return _dayMonthYear.format(date);
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
