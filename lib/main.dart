import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/theme.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/login_screen.dart';
import 'features/onboarding/onboarding_wizard.dart';
import 'features/dashboard/dashboard_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authServiceProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Net Worth Tracker',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: _getHomeWidget(authState.status),
    );
  }

  Widget _getHomeWidget(AuthStatus status) {
    switch (status) {
      case AuthStatus.uninitialized:
        return const OnboardingWizard();
      case AuthStatus.locked:
        return const LoginScreen();
      case AuthStatus.authenticated:
        return const DashboardView();
    }
  }
}
