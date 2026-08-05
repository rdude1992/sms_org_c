import 'package:flutter/material.dart';

enum SmsCategory { personal, promotional, transactional, otp }

extension SmsCategoryX on SmsCategory {
  String get label {
    switch (this) {
      case SmsCategory.personal:
        return 'Personal';
      case SmsCategory.promotional:
        return 'Promotions';
      case SmsCategory.transactional:
        return 'Transactions';
      case SmsCategory.otp:
        return 'OTP';
    }
  }

  IconData get icon {
    switch (this) {
      case SmsCategory.personal:
        return Icons.person_outline;
      case SmsCategory.promotional:
        return Icons.local_offer_outlined;
      case SmsCategory.transactional:
        return Icons.currency_rupee;
      case SmsCategory.otp:
        return Icons.password_outlined;
    }
  }

  Color get color {
    switch (this) {
      case SmsCategory.personal:
        return const Color(0xFF6366F1); // indigo
      case SmsCategory.promotional:
        return const Color(0xFFF59E0B); // amber
      case SmsCategory.transactional:
        return const Color(0xFF10B981); // emerald
      case SmsCategory.otp:
        return const Color(0xFF8B5CF6); // violet
    }
  }
}
