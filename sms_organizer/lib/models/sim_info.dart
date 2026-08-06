/// An active SIM on a dual-SIM device, as reported by SubscriptionManager on
/// the native side. [slotIndex] is 0-based ("SIM 1" = 0, "SIM 2" = 1);
/// [subscriptionId] is the opaque id SmsManager/the SMS provider actually
/// key on internally and is what gets sent back when choosing a SIM to send
/// from.
class SimInfo {
  final int subscriptionId;
  final int slotIndex;
  final String displayName;
  final String? carrierName;

  SimInfo({
    required this.subscriptionId,
    required this.slotIndex,
    required this.displayName,
    this.carrierName,
  });

  factory SimInfo.fromPlatformMap(Map<dynamic, dynamic> map) {
    return SimInfo(
      subscriptionId: map['subscriptionId'] as int,
      slotIndex: map['slotIndex'] as int,
      displayName: (map['displayName'] as String?) ?? 'SIM ${(map['slotIndex'] as int) + 1}',
      carrierName: map['carrierName'] as String?,
    );
  }

  /// "SIM 1", "SIM 2", ... — the label shown throughout the UI regardless of
  /// what the carrier calls itself, so both SIM slots read consistently.
  String get label => 'SIM ${slotIndex + 1}';
}
