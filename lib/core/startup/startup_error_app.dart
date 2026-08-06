import 'dart:ui';

import 'package:flutter/material.dart';

class StartupErrorApp extends StatefulWidget {
  const StartupErrorApp({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    final isArabic = PlatformDispatcher.instance.locale.languageCode == 'ar';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 54),
                          const SizedBox(height: 20),
                          Text(
                            isArabic
                                ? 'تعذر تشغيل التطبيق'
                                : 'The application could not start',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isArabic
                                ? 'تحقق من اتصالك ثم حاول مرة أخرى. لم يتم إجراء أي تغيير على بياناتك.'
                                : 'Check your connection and try again. No changes were made to your data.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _retrying ? null : _retry,
                            icon: _retrying
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
    if (mounted) setState(() => _retrying = false);
  }
}
