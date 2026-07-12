import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'about.dart';
import 'bms_state.dart';
import 'screens/cells_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';
import 'theme.dart';
import 'widgets.dart';

export 'ble.dart';
export 'bms_state.dart';
export 'jbd_bms.dart';
export 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // BLE plugins can surface transient platform errors on detached futures
  // (e.g. a write racing a disconnect). Log them instead of letting an
  // uncaught async error take down the release app.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  runApp(const ProviderScope(child: BmsApp()));
}

class BmsApp extends StatelessWidget {
  const BmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMS Dash',
      debugShowCheckedModeBanner: false,
      theme: buildBmsTheme(),
      home: const _Home(),
    );
  }
}

class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected =
        ref.watch(bmsControllerProvider.select((s) => s.isConnected));
    return isConnected ? const ConnectedShell() : const ConnectScreen();
  }
}

/// Tabbed shell shown while a BMS session is live.
class ConnectedShell extends ConsumerStatefulWidget {
  const ConnectedShell({super.key});

  @override
  ConsumerState<ConnectedShell> createState() => _ConnectedShellState();
}

class _ConnectedShellState extends ConsumerState<ConnectedShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bmsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GradientBoltMark(),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                state.deviceName ?? 'BMS Dash',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (state.isDemo) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: BmsColors.purple.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'DEMO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: BmsColors.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About & support',
            onPressed: () => showAboutBmsDialog(context),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Disconnect',
            onPressed: () =>
                ref.read(bmsControllerProvider.notifier).disconnect(),
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: const [
            DashboardScreen(),
            CellsScreen(),
            MonitorScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.stacked_bar_chart),
            label: 'Cells',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Monitor',
          ),
        ],
      ),
    );
  }
}
