import 'package:intl/intl.dart';

class Formatters {
  static final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _currencyPrecise =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _dayMonth = DateFormat('d MMM');
  static final _timeOfDay = DateFormat('h:mm a');
  static final _fullDate = DateFormat('d MMM yyyy, h:mm a');
  static final _monthYear = DateFormat('MMM yyyy');

  static String currency(double value) => _currency.format(value);
  static String currencyPrecise(double value) => _currencyPrecise.format(value);
  static String monthYear(DateTime date) => _monthYear.format(date);
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
}
