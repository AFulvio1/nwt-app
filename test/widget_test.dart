import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nwt_app/main.dart';
import 'package:nwt_app/features/auth/auth_service.dart';
import 'package:nwt_app/features/onboarding/onboarding_wizard.dart';

// Mock AuthService to isolate UI tests from native method channels
class MockAuthService extends AuthService {
  final AuthStatus mockStatus;

  MockAuthService(this.mockStatus);

  @override
  AuthState build() {
    return AuthState(
      status: mockStatus,
      isBiometricsAvailable: false,
      isBiometricsEnabled: false,
    );
  }
}

void main() {
  testWidgets('App onboarding wizard smoke test', (WidgetTester tester) async {
    // Build our app with Riverpod overrides to force Uninitialized auth state
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith(() => MockAuthService(AuthStatus.uninitialized)),
        ],
        child: const MyApp(),
      ),
    );

    // Pump pending frames
    await tester.pumpAndSettle();

    // Verify that the setup wizard screen is shown
    expect(find.byType(OnboardingWizard), findsOneWidget);
    expect(find.text('Setup Wizard'), findsOneWidget);
  });
}
