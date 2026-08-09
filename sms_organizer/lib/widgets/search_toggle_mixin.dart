import 'package:flutter/material.dart';

/// Adds a toggleable search field to an AppBar — tap the search icon to
/// swap the title for a text field, tap close to go back to the plain
/// title. Shared by every drilldown screen that lets the user search its
/// own list (Transaction/Merchant/Instrument/Investment), so the
/// toggle-state plumbing (are we searching, what's typed, wiring the
/// controller) exists in exactly one place instead of once per screen —
/// mirrors the pattern InboxScreen already has inline for itself.
mixin SearchToggleMixin<T extends StatefulWidget> on State<T> {
  bool isSearching = false;
  final TextEditingController searchController = TextEditingController();
  String query = '';

  void startSearch() => setState(() => isSearching = true);

  void stopSearch() {
    searchController.clear();
    setState(() {
      query = '';
      isSearching = false;
    });
  }

  void onSearchChanged(String value) => setState(() => query = value);

  /// Call from the mixing-in State's dispose().
  void disposeSearch() => searchController.dispose();

  /// AppBar title: the search field when active, [title] otherwise.
  Widget searchAppBarTitle(String title, {required String hintText}) {
    if (!isSearching) return Text(title);
    return TextField(
      controller: searchController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(hintText: hintText, border: InputBorder.none),
      onChanged: onSearchChanged,
    );
  }

  /// AppBar actions: the search/close icon toggle — spread this into an
  /// existing actions list, e.g. `actions: [...searchAppBarActions()]`.
  List<Widget> searchAppBarActions() {
    return [
      if (isSearching)
        IconButton(icon: const Icon(Icons.close), onPressed: stopSearch)
      else
        IconButton(icon: const Icon(Icons.search), onPressed: startSearch),
    ];
  }
}
