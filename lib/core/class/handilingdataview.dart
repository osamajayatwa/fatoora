import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:flutter/material.dart';

class HandilingDataView extends StatelessWidget {
  const HandilingDataView({
    super.key,
    required this.statusrequest,
    required this.widget,
    this.onRetry,
    this.errorMessage,
    this.retryLabel,
  });
  final StatusRequest statusrequest;
  final Widget widget;
  final VoidCallback? onRetry;
  final String? errorMessage;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    if (statusrequest == StatusRequest.none ||
        statusrequest == StatusRequest.success) {
      return widget;
    }

    final state = switch (statusrequest) {
      StatusRequest.loading => _HandlingStateKind.loading,
      StatusRequest.offlinefailure => _HandlingStateKind.offline,
      StatusRequest.failure => _HandlingStateKind.empty,
      _ => _HandlingStateKind.error,
    };

    return _HandlingState(
      state: state,
      message: errorMessage,
      retryLabel: retryLabel,
      onRetry: onRetry,
    );
  }
}

class _HandlingState extends StatelessWidget {
  const _HandlingState({
    required this.state,
    this.message,
    this.retryLabel,
    this.onRetry,
  });

  final _HandlingStateKind state;
  final String? message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final loading = state == _HandlingStateKind.loading;
    final scheme = Theme.of(context).colorScheme;
    return FatooraMotionReveal(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: .12),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 88,
                  child: Center(
                    child: loading
                        ? const FatooraProgressIndicator(size: 34)
                        : Icon(_icon, size: 38, color: scheme.primary),
                  ),
                ),
              ),
              if (!loading && message != null) ...[
                const SizedBox(height: 16),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (!loading && onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(retryLabel ?? 'Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (state) {
    _HandlingStateKind.loading => Icons.hourglass_top_rounded,
    _HandlingStateKind.offline => Icons.cloud_off_outlined,
    _HandlingStateKind.empty => Icons.inbox_outlined,
    _HandlingStateKind.error => Icons.sync_problem_outlined,
  };
}

enum _HandlingStateKind { loading, offline, empty, error }

class HandilingDataRequest extends StatelessWidget {
  const HandilingDataRequest({
    super.key,
    required this.statusrequest,
    required this.widget,
  });
  final StatusRequest statusrequest;
  final Widget widget;

  @override
  Widget build(BuildContext context) {
    if (statusrequest == StatusRequest.loading) {
      return const Center(child: FatooraProgressIndicator(size: 34));
    }
    if (statusrequest == StatusRequest.offlinefailure ||
        statusrequest == StatusRequest.serverfailure ||
        statusrequest == StatusRequest.timeout ||
        statusrequest == StatusRequest.unauthorized) {
      return Center(
        child: Icon(
          Icons.sync_problem_outlined,
          size: 42,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return widget;
  }
}
