import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sim_info.dart';
import '../providers/sms_provider.dart';
import '../widgets/sim_picker.dart';
import 'contact_picker_screen.dart';

class ComposeScreen extends StatefulWidget {
  final String? initialAddress;
  final String? initialBody;

  const ComposeScreen({super.key, this.initialAddress, this.initialBody});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final _toController = TextEditingController(text: widget.initialAddress ?? '');
  late final _bodyController = TextEditingController(text: widget.initialBody ?? '');
  bool _sending = false;
  int? _selectedSubscriptionId;
  bool _simInitialized = false;

  @override
  void dispose() {
    _toController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _initSelectedSim(List<SimInfo> sims) {
    if (_simInitialized) return;
    _simInitialized = true;
    if (sims.isNotEmpty) _selectedSubscriptionId = sims.first.subscriptionId;
  }

  Future<void> _pickContact() async {
    final number = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ContactPickerScreen()),
    );
    if (number != null) {
      setState(() => _toController.text = number);
    }
  }

  Future<void> _send() async {
    final address = _toController.text.trim();
    final body = _bodyController.text.trim();
    if (address.isEmpty || body.isEmpty) return;

    setState(() => _sending = true);
    final ok = await context
        .read<SmsProvider>()
        .sendSms(address, body, subscriptionId: _selectedSubscriptionId);
    setState(() => _sending = false);
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _saveDraft() async {
    final address = _toController.text.trim();
    final body = _bodyController.text.trim();
    if (address.isEmpty || body.isEmpty) {
      Navigator.pop(context);
      return;
    }
    await context.read<SmsProvider>().saveDraft(address, body);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final sims = context.watch<SmsProvider>().activeSims;
    _initSelectedSim(sims);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New message'),
        actions: [
          TextButton(onPressed: _saveDraft, child: const Text('Save draft')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _toController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _pickContact,
                  icon: const Icon(Icons.contacts_outlined),
                  tooltip: 'Pick contact',
                ),
              ],
            ),
            if (sims.length > 1) ...[
              const SizedBox(height: 12),
              SimPicker(
                sims: sims,
                selectedSubscriptionId: _selectedSubscriptionId,
                onChanged: (id) => setState(() => _selectedSubscriptionId = id),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _bodyController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
