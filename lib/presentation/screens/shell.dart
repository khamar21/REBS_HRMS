import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'leave_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final contentWidth = width > 760 ? 720.0 : width;
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: contentWidth,
          child: IndexedStack(
            index: _index,
            children: const [HomeScreen(), LeaveScreen()],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.beach_access_outlined),
              selectedIcon: Icon(Icons.beach_access_rounded),
              label: 'Leave',
            ),
          ],
        ),
      ),
    );
  }
}
