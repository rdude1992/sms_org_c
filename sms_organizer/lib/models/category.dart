import 'package:flutter/material.dart';

/// Mirrors the 5-category model from the ported classifier (see
/// lib/services/categorization_service.dart): the original 4-category
/// scheme didn't have anywhere to put delivery notifications, bill/due-date
/// reminders, booking confirmations, and account statements — these aren't
/// personal chat, aren't promotions, and aren't financial transactions
/// either. `updates` covers that bucket, and is also the default fallback
/// for anything else that doesn't clearly match one of the other four.
enum SmsCategory { personal, promotional, transactional, otp, updates }

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
      case SmsCategory.updates:
        return 'Updates';
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
      case SmsCategory.updates:
        return Icons.notifications_outlined;
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
      case SmsCategory.updates:
        return const Color(0xFF64748B); // slate
    }
  }
}
