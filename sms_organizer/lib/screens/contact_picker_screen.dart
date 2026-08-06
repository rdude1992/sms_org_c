import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import '../services/contact_service.dart';

/// Full-screen searchable contact list. Pops with the selected contact's
/// phone number (a String), or null if dismissed without a pick.
class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<SmsProvider>().contactService.entries;
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? contacts
        : contacts
            .where((c) =>
                c.name.toLowerCase().contains(query) || c.number.replaceAll(' ', '').contains(query))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search contacts',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: contacts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No contacts found. Make sure contacts permission is granted.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : filtered.isEmpty
              ? const Center(child: Text('No matching contacts.'))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final contact = filtered[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      minVerticalPadding: 10,
                      leading: CircleAvatar(
                        radius: 20,
                        child: Text(contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?'),
                      ),
                      title: Text(contact.name),
                      subtitle: Text(contact.number),
                      onTap: () => Navigator.pop(context, contact.number),
                    );
                  },
                ),
    );
  }
}
