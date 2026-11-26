import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';

class BudgetApp extends ConsumerStatefulWidget {
  const BudgetApp({super.key});

  @override
  ConsumerState<BudgetApp> createState() => _BudgetAppState();
}

class _BudgetAppState extends ConsumerState<BudgetApp>
    with WidgetsBindingObserver {
  late final _router = buildRouter();
  late Future<void> _startup;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup = _initialize();
  }

  Future<void> _initialize() async {
    await ref.read(databaseProvider).seedIfEmpty();
    if (!mounted) return;
    _seeded = true;
    unawaited(ref.read(fxServiceProvider).refreshIfNeeded());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_seeded && state == AppLifecycleState.resumed) {
      unawaited(ref.read(fxServiceProvider).refreshIfNeeded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Hazir',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: _router,
      builder: (context, child) => FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not open your ledger.'),
                    TextButton(
                      onPressed: () => setState(() {
                        _startup = _initialize();
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold();
          }
          return child!;
        },
      ),
    );
  }
}
