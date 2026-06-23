import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/imageassests.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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

    final asset = switch (statusrequest) {
      StatusRequest.loading => ImageAssest.loading,
      StatusRequest.offlinefailure => ImageAssest.offline,
      StatusRequest.failure => ImageAssest.noData,
      _ => ImageAssest.server,
    };

    return _HandlingState(
      asset: asset,
      loading: statusrequest == StatusRequest.loading,
      message: errorMessage,
      retryLabel: retryLabel,
      onRetry: onRetry,
    );
  }
}

class _HandlingState extends StatelessWidget {
  const _HandlingState({
    required this.asset,
    required this.loading,
    this.message,
    this.retryLabel,
    this.onRetry,
  });

  final String asset;
  final bool loading;
  final String? message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(asset, width: 120, height: 120),
            if (!loading && message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (!loading && onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel ?? 'Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
      return Center(
        child: Lottie.asset(ImageAssest.loading, width: 100, height: 100),
      );
    }
    if (statusrequest == StatusRequest.offlinefailure ||
        statusrequest == StatusRequest.serverfailure ||
        statusrequest == StatusRequest.timeout ||
        statusrequest == StatusRequest.unauthorized) {
      return Center(
        child: Lottie.asset(ImageAssest.server, width: 100, height: 100),
      );
    }
    return widget;
  }
}
