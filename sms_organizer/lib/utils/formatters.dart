import 'package:intl/intl.dart';

class Formatters {
  static final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _currencyPrecise =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _dayOnly = DateFormat('d');
  static final _dayMonth = DateFormat('d MMM');
  static final _dayMonthYear = DateFormat('d MMM yyyy');
  static final _timeOfDay = DateFormat('h:mm a');
  static final _fullDate = DateFormat('d MMM yyyy, h:mm a');
  static final _monthYear = DateFormat('MMM yyyy');

  static String currency(double value) => _currency.format(value);
  static String currencyPrecise(double value) => _currencyPrecise.format(value);
  static String monthYear(DateTime date) => _monthYear.format(date);
  static String dayOnly(DateTime date) => _dayOnly.format(date);
  static String dayMonth(DateTime date) => _dayMonth.format(date);
  static String dayMonthYear(DateTime date) => _dayMonthYear.format(date);
  static String timeOfDay(DateTime date) => _timeOfDay.format(date);

  static String relativeOrTime(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return _timeOfDay.format(date);
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day;
    if (isYesterday) return 'Yesterday';
    return _dayMonth.format(date);
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
