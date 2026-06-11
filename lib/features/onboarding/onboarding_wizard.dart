import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/database.dart';
import '../auth/auth_service.dart';

class OnboardingWizard extends ConsumerStatefulWidget {
  const OnboardingWizard({super.key});

  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Step 1: PIN State
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _enableBiometrics = false;

  // Step 2: Currency State
  String _selectedCurrency = 'EUR';
  final List<String> _currencies = ['EUR', 'USD', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD'];

  // Step 3: Template State
  String _selectedTemplate = 'personal'; // personal, business, empty

  @override
  void dispose() {
    _pageController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    final pin = _pinController.text;
    final confirmPin = _confirmPinController.text;

    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode must be at least 4 digits')),
      );
      return;
    }

    if (pin != confirmPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcodes do not match')),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final db = ref.read(databaseProvider);

      // 1. Seed database with base currency and default categories/accounts
      await db.seedInitialData(_selectedCurrency);

      // Apply custom templates if needed
      if (_selectedTemplate == 'business') {
        await db.transaction(() async {
          // Add standard business accounts
          final revenueMacros = await (db.select(db.macroCategories)..where((t) => t.type.equals('Revenue'))).get();
          final expenseMacros = await (db.select(db.macroCategories)..where((t) => t.type.equals('Expense'))).get();
          final assetMacros = await (db.select(db.macroCategories)..where((t) => t.type.equals('Asset'))).get();

          final revId = revenueMacros.first.id;
          final expId = expenseMacros.first.id;
          final assetId = assetMacros.first.id;

          final salesCat = await db.into(db.categories).insert(CategoriesCompanion(
            macroCategoryId: drift.Value(revId),
            name: const drift.Value('Sales Revenue'),
          ));
          final opsCat = await db.into(db.categories).insert(CategoriesCompanion(
            macroCategoryId: drift.Value(expId),
            name: const drift.Value('Operating Expenses'),
          ));
          final receivableCat = await db.into(db.categories).insert(CategoriesCompanion(
            macroCategoryId: drift.Value(assetId),
            name: const drift.Value('Accounts Receivable'),
          ));

          await db.into(db.accounts).insert(AccountsCompanion(
            categoryId: drift.Value(salesCat),
            name: const drift.Value('Client Billing'),
            currency: drift.Value(_selectedCurrency),
          ));
          await db.into(db.accounts).insert(AccountsCompanion(
            categoryId: drift.Value(opsCat),
            name: const drift.Value('Software Subscriptions'),
            currency: drift.Value(_selectedCurrency),
          ));
          await db.into(db.accounts).insert(AccountsCompanion(
            categoryId: drift.Value(receivableCat),
            name: const drift.Value('Outstanding Invoices'),
            currency: drift.Value(_selectedCurrency),
          ));
        });
      }

      // 2. Save PIN and set biometrics status in secure storage
      final authService = ref.read(authServiceProvider.notifier);
      final success = await authService.registerPasscode(pin, _enableBiometrics);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.read(authServiceProvider).errorMessage ?? 'Registration failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // Close loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during initialization: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authServiceProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Progress Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Setup Wizard',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    'Step ${_currentStep + 1} of 3',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Custom progress bar
              Row(
                children: List.generate(3, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        left: index > 0 ? 8 : 0,
                        right: index < 2 ? 8 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: _currentStep >= index
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),

              // Step Content Pages
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) {
                    setState(() {
                      _currentStep = page;
                    });
                  },
                  children: [
                    _buildStep1Auth(authState),
                    _buildStep2Currency(),
                    _buildStep3Template(),
                  ],
                ),
              ),

              // Navigation Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    TextButton.icon(
                      onPressed: _prevPage,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    onPressed: () {
                      if (_currentStep < 2) {
                        // Validate current page before moving
                        if (_currentStep == 0) {
                          if (_pinController.text.length < 4) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('PIN must be at least 4 digits')),
                            );
                            return;
                          }
                          if (_pinController.text != _confirmPinController.text) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('PINs do not match')),
                            );
                            return;
                          }
                        }
                        _nextPage();
                      } else {
                        _completeOnboarding();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _currentStep == 2 ? 'Finish Setup' : 'Continue',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 1: Authentication UI
  Widget _buildStep1Auth(AuthState authState) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Secure Your Ledger',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Create a 4-digit passcode to secure your financial data locally on this device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Choose Passcode',
              prefixIcon: Icon(Icons.lock_outline),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmPinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm Passcode',
              prefixIcon: Icon(Icons.lock_reset),
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          if (authState.isBiometricsAvailable)
            SwitchListTile(
              title: const Text('Enable Biometrics'),
              subtitle: const Text('Unlock quickly using Fingerprint or Face ID'),
              value: _enableBiometrics,
              onChanged: (val) {
                setState(() {
                  _enableBiometrics = val;
                });
              },
              secondary: const Icon(Icons.fingerprint),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Biometrics not available or not supported on this device.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Step 2: Currency UI
  Widget _buildStep2Currency() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Base Currency',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Select the main reference currency for your ledger. All assets and liabilities will be consolidated into this currency on your dashboard.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        Expanded(
          child: ListView.builder(
            itemCount: _currencies.length,
            itemBuilder: (context, index) {
              final currency = _currencies[index];
              final isSelected = _selectedCurrency == currency;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  title: Text(
                    currency,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedCurrency = currency;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Step 3: Template UI
  Widget _buildStep3Template() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Account Template',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a starting structure for your accounts and categories. You can fully customize these later.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        _buildTemplateOption(
          id: 'personal',
          title: 'Personal Finance Template',
          description: 'Cash, Bank Accounts, Groceries, Rent, Salary, Credit Cards. Recommended for general use.',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),
        _buildTemplateOption(
          id: 'business',
          title: 'Business Ledger Template',
          description: 'Client Billing, Software Subscriptions, Outstanding Invoices, and Operations categories.',
          icon: Icons.business_center_outlined,
        ),
        const SizedBox(height: 16),
        _buildTemplateOption(
          id: 'empty',
          title: 'Clean Slate',
          description: 'Only seeds basic root asset, liability, and equity groups. No pre-made accounts.',
          icon: Icons.star_border,
        ),
      ],
    );
  }

  Widget _buildTemplateOption({
    required String id,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final isSelected = _selectedTemplate == id;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _selectedTemplate = id;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 28,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
            ],
          ),
        ),
      ),
    );
  }
}
