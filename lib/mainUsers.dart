import 'package:flutter/material.dart';
import 'package:shnell/Account.dart';
import 'package:shnell/History.dart';
import 'package:shnell/drawer.dart';
import 'package:shnell/tabsControlerMultipleAsignements.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class MainUsersScreen extends StatefulWidget {
  final int? initialIndex;

  const MainUsersScreen({super.key, this.initialIndex});

  @override
  State<MainUsersScreen> createState() => _MainUsersScreenState();
}

class _MainUsersScreenState extends State<MainUsersScreen> {
  late int _currentIndex;
  final List<Widget> _tabs = [
    const MultipleTrackingScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
  }

@override
Widget build(BuildContext context) {
  // Get the localization instance.
  final l10n = AppLocalizations.of(context)!;

  return Scaffold(
    drawer: ShnellDrawer(initialIndex: _currentIndex),
    body: IndexedStack(
      index: _currentIndex,
      children: _tabs,
    ),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          label: l10n.home, // Use the 'home' key
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history_edu_outlined , size: 26,),
          label: l10n.history, // Use the 'history' key
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outlined),
          label: l10n.account, // Use the 'account' key
        ),
      ],
      selectedItemColor: const Color.fromARGB(255, 255, 191, 0),
      unselectedItemColor: const Color.fromARGB(255, 197, 197, 195),
      type: BottomNavigationBarType.fixed,
    ),
  );
}
}
