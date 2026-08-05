import 'package:flutter/material.dart';

/// General-purpose navigator key for MaterialApp. Not currently required by
/// any specific feature — notification-tap navigation is handled directly
/// by HomeScreen via its own BuildContext — but kept as standard
/// infrastructure for anything that later needs to navigate without one
/// (e.g. a global snackbar or dialog triggered from outside the widget tree).
final navigatorKey = GlobalKey<NavigatorState>();
