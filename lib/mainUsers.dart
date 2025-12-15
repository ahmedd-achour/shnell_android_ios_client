
import 'package:flutter/material.dart';
import 'package:shnell/Account.dart';
import 'package:shnell/History.dart';
import 'package:shnell/drawer.dart';
import 'package:shnell/tabsControlerMultipleAsignements.dart';

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
    const UserActivityDashboard(),
    const SettingsScreen(),
  ];

  // This will be set when an incoming call is active

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
  }


  @override
  Widget build(BuildContext context) {

    return Scaffold(
      drawer: ShnellDrawer(initialIndex: _currentIndex),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
    /*  bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            label: l10n.home,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history_edu_outlined, size: 26),
            label: l10n.history,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outlined),
            label: l10n.account,
          ),
        ],
        selectedItemColor: const Color.fromARGB(255, 187, 152, 48),
        unselectedItemColor: const Color.fromARGB(255, 197, 197, 195),
        type: BottomNavigationBarType.fixed,
      ),*/
    );
  }

}