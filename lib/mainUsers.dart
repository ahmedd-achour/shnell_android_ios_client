import 'package:flutter/material.dart';
import 'package:shnell/Account.dart';
import 'package:shnell/History.dart';
import 'package:shnell/drawer.dart';
import 'package:shnell/tabsControlerMultipleAsignements.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class MainUsersScreen extends StatelessWidget {
  final int? initialIndex;

  const MainUsersScreen({super.key, this.initialIndex});

  @override

  Widget build(BuildContext context) {
   


  // Otherwise → normal driver interface
        return _MainTabsContent(initialIndex: initialIndex ?? 0);         
      }
}
// Separate widget for the main tab interface
class _MainTabsContent extends StatefulWidget {
  final int initialIndex;
  const _MainTabsContent({required this.initialIndex});

  @override
  State<_MainTabsContent> createState() => _MainTabsContentState();
}

class _MainTabsContentState extends State<_MainTabsContent> {
  late int _currentIndex;

  final List<Widget> _tabs = const [
    SingleBookingScreen(),
    UserActivityDashboard(),
    SettingsScreen(),
  ];

  @override

  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      drawer: const ShnellDrawer(),
      extendBodyBehindAppBar: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: l10n.home),
          BottomNavigationBarItem(icon: Icon(Icons.history_edu_outlined, size: 26), label: l10n.history),
          BottomNavigationBarItem(icon: Icon(Icons.person_outlined), label: l10n.account),
        ],
        selectedItemColor: const Color.fromARGB(255, 187, 152, 48),
        unselectedItemColor: const Color.fromARGB(255, 197, 197, 195),
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}