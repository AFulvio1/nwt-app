import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final List<int> _enteredDigits = [];

  void _onDigitPressed(int digit) {
    if (_enteredDigits.length < 6) {
      setState(() {
        _enteredDigits.add(digit);
      });
      if (_enteredDigits.length >= 4) {
        _verifyPin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_enteredDigits.isNotEmpty) {
      setState(() {
        _enteredDigits.removeLast();
      });
    }
  }

  Future<void> _verifyPin() async {
    final pinStr = _enteredDigits.join();
    final authService = ref.read(authServiceProvider.notifier);
    
    // We try to verify. If it fails, we clear the entries after a short delay
    final success = await authService.verifyPasscode(pinStr);
    if (!success) {
      // Small vibration/delay and clear
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _enteredDigits.clear();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authServiceProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  // Header logo / title
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'NET WORTH TRACKER',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter passcode to unlock your ledger',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),

                  // PIN Indicators (Circles)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isFilled = index < _enteredDigits.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  
                  // Error feedback
                  if (authState.errorMessage != null)
                    Text(
                      authState.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    const SizedBox(height: 17),

                  const SizedBox(height: 24),

                  // Custom Keypad Grid
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKeypadButton(1),
                          _buildKeypadButton(2),
                          _buildKeypadButton(3),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKeypadButton(4),
                          _buildKeypadButton(5),
                          _buildKeypadButton(6),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKeypadButton(7),
                          _buildKeypadButton(8),
                          _buildKeypadButton(9),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Left utility key: Biometrics or empty
                          authState.isBiometricsEnabled && authState.isBiometricsAvailable
                              ? _buildBiometricKey()
                              : const SizedBox(width: 70, height: 70),
                          _buildKeypadButton(0),
                          _buildBackspaceKey(),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadButton(int digit) {
    return SizedBox(
      width: 70,
      height: 70,
      child: OutlinedButton(
        onPressed: () => _onDigitPressed(digit),
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.5),
          backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.4),
        ),
        child: Text(
          '$digit',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onBackground,
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricKey() {
    return SizedBox(
      width: 70,
      height: 70,
      child: IconButton(
        onPressed: () {
          ref.read(authServiceProvider.notifier).authenticateWithBiometrics();
        },
        icon: Icon(
          Icons.fingerprint,
          size: 32,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return SizedBox(
      width: 70,
      height: 70,
      child: IconButton(
        onPressed: _onBackspacePressed,
        icon: Icon(
          Icons.backspace_outlined,
          size: 24,
          color: Theme.of(context).colorScheme.onBackground,
        ),
      ),
    );
  }
}
