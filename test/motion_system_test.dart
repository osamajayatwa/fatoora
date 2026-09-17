import 'dart:io';

import 'package:fatoora/core/motion/fatoora_motion.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/motion/fatoora_page_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('motion tokens stay within the app performance budget', () {
    expect(FatooraMotion.quick.inMilliseconds, 150);
    expect(FatooraMotion.standard.inMilliseconds, 200);
    expect(FatooraMotion.page.inMilliseconds, 250);
    expect(FatooraMotion.deliberate.inMilliseconds, 300);
  });

  testWidgets('surface motion is omitted when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _MotionTestApp(
        disableAnimations: true,
        child: FatooraMotionReveal(child: Text('content')),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    expect(find.byType(Animate), findsNothing);
  });

  testWidgets('surface motion uses flutter_animate when enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _MotionTestApp(child: FatooraMotionReveal(child: Text('content'))),
    );

    expect(find.byType(Animate), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('state switcher and progress become motionless on request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _MotionTestApp(
        disableAnimations: true,
        child: Column(
          children: [
            FatooraMotionSwitcher(child: Text('state')),
            FatooraProgressIndicator(),
          ],
        ),
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
  });

  testWidgets('page transition is immediate when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _MotionTestApp(
        disableAnimations: true,
        child: Builder(
          builder: (context) => FatooraPageTransition().buildTransition(
            context,
            null,
            null,
            const AlwaysStoppedAnimation(1),
            const AlwaysStoppedAnimation(0),
            const Text('destination'),
          ),
        ),
      ),
    );

    expect(find.text('destination'), findsOneWidget);
    expect(find.byType(FadeTransition), findsNothing);
    expect(find.byType(SlideTransition), findsNothing);
  });

  test('obsolete Lottie integration stays removed', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(pubspec, contains('flutter_animate:'));
    expect(pubspec, isNot(contains('\n  lottie:')));
    expect(source, isNot(contains('package:lottie/')));
    expect(source, isNot(contains('AnimationController')));
  });
}

class _MotionTestApp extends StatelessWidget {
  const _MotionTestApp({required this.child, this.disableAnimations = false});

  final Widget child;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    );
  }
}
