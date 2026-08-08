import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sim_info.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';
import '../services/contact_service.dart';
import '../widgets/sim_picker.dart';
import 'contact_picker_screen.dart';
import 'thread_screen.dart';

/// Composing a message to a number that already has a thread is really just
/// opening that thread — this screen only exists for the moment before a
/// recipient is chosen (or for a genuinely new number). As soon as one is
/// picked and it matches an existing conversation, control hands off to the
/// real ThreadScreen (see [_goToExistingThreadIfAny]) so the two never
/// duplicate each other's bubble list / reply bar / draft handling.
class ComposeScreen extends StatefulWidget {
  final String? initialAddress;
  final String? initialBody;

  const ComposeScreen({super.key, this.initialAddress, this.initialBody});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final _toController = TextEditingController(text: widget.initialAddress ?? '');
  final _toFocusNode = FocusNode();
  late final _bodyController = TextEditingController(text: widget.initialBody ?? '');
  bool _sending = false;
  int? _selectedSubscriptionId;
  bool _simInitialized = false;

  @override
  void initState() {
    super.initState();
    // Arriving here with an address already filled in (forwarding a
    // message, an sms: deep link) is the same "a recipient is known" case
    // as picking one from the field below — check once the first frame is
    // up so Navigator is safe to use.
    final initialAddress = widget.initialAddress?.trim();
    if (initialAddress != null && initialAddress.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToExistingThreadIfAny(initialAddress);
      });
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _toFocusNode.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _initSelectedSim(List<SimInfo> sims) {
    if (_simInitialized) return;
    _simInitialized = true;
    if (sims.isNotEmpty) _selectedSubscriptionId = sims.first.subscriptionId;
  }

  SmsConversation? _existingConversationFor(String address) {
    final normalized = ContactService.normalize(address);
    if (normalized.isEmpty) return null;
    final conversations = context.read<SmsProvider>().conversations;
    for (final c in conversations) {
      if (ContactService.normalize(c.address) == normalized) return c;
    }
    return null;
  }

  /// If [address] already has a thread, replaces this screen with the real
  /// ThreadScreen for it — carrying over any message already typed here so
  /// picking a contact never loses in-progress text. Returns whether it
  /// navigated.
  bool _goToExistingThreadIfAny(String address) {
    final existing = _existingConversationFor(address);
    if (existing == null) return false;
    final draftText = _bodyController.text.trim();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(
          threadId: existing.threadId,
          initialReplyText: draftText.isEmpty ? null : draftText,
        ),
      ),
    );
    return true;
  }

  Future<void> _pickContact() async {
    final number = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ContactPickerScreen()),
    );
    if (number == null) return;
    if (_goToExistingThreadIfAny(number)) return;
    setState(() => _toController.text = number);
  }

  Future<void> _send() async {
    final address = _toController.text.trim();
    final body = _bodyController.text.trim();
    if (address.isEmpty || body.isEmpty) return;

    setState(() => _sending = true);
    final provider = context.read<SmsProvider>();
    final ok = await provider.sendSms(address, body, subscriptionId: _selectedSubscriptionId);
    setState(() => _sending = false);
    if (!ok || !mounted) return;

    // The message just sent means this address now has a thread (new or
    // pre-existing) — hand off to it so sending continues like any other
    // chat instead of dead-ending back on an empty compose screen.
    final thread = _existingConversationFor(address);
    if (thread != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ThreadScreen(threadId: thread.threadId)),
      );
    } else {
      Navigator.pop(context);
    }
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RawAutocomplete<ContactEntry>(
                    textEditingController: _toController,
                    focusNode: _toFocusNode,
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      if (query.isEmpty) return const Iterable<ContactEntry>.empty();
                      final contacts = context.read<SmsProvider>().contactService.entries;
                      return contacts
                          .where((c) =>
                              c.name.toLowerCase().contains(query) ||
                              c.number.replaceAll(RegExp(r'\s'), '').contains(query))
                          .take(6);
                    },
                    displayStringForOption: (c) => c.number,
                    onSelected: (c) {
                      if (_goToExistingThreadIfAny(c.number)) return;
                      _toController.text = c.number;
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'To'),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final c = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    child: Text(
                                      c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  title: Text(c.name),
                                  subtitle: Text(c.number),
                                  onTap: () => onSelected(c),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
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
          ),
          const Divider(height: 1),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Type a number or pick a contact to start chatting.\n'
                  'Picking a contact with an existing conversation opens it directly.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // Reply bar — same layout as ThreadScreen's, so composing a
          // brand-new message looks and behaves like continuing an
          // existing chat rather than a separate "form" experience.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  if (sims.length > 1) ...[
                    SimPicker(
                      sims: sims,
                      selectedSubscriptionId: _selectedSubscriptionId,
                      onChanged: (id) => setState(() => _selectedSubscriptionId = id),
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _bodyController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: _sending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
