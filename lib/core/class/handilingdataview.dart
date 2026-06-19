import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constant/imageassests.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';


class HandilingDataView extends StatelessWidget {
  const HandilingDataView({
    super.key,
    required this.statusrequest,
    required this.widget,
  });
  final StatusRequest statusrequest;
  final Widget widget;

  @override
  Widget build(BuildContext context) {
    return statusrequest == StatusRequest.loading
        ? Center(
            child: Lottie.asset(ImageAssest.loading, width: 100, height: 100))
        : statusrequest == StatusRequest.offlinefailure
            ? Center(
                child:
                    Lottie.asset(ImageAssest.offline, width: 100, height: 100),
              )
            : statusrequest == StatusRequest.serverfailure
                ? Center(
                    child: Lottie.asset(ImageAssest.server,
                        width: 100, height: 100),
                  )
                : statusrequest == StatusRequest.failure
                    ? Center(
                        child: Lottie.asset(ImageAssest.noData,
                            width: 100, height: 100),
                      )
                    : widget;
  }
}

class HandilingDataRequest extends StatelessWidget {
  const HandilingDataRequest(
      {super.key, required this.statusrequest, required this.widget});
  final StatusRequest statusrequest;
  final Widget widget;

  @override
  Widget build(BuildContext context) {
    return statusrequest == StatusRequest.loading
        ? Center(
            child: Lottie.asset(ImageAssest.loading, width: 100, height: 100))
        : statusrequest == StatusRequest.offlinefailure
            ? Center(
                child:
                    Lottie.asset(ImageAssest.offline, width: 100, height: 100),
              )
            : statusrequest == StatusRequest.serverfailure
                ? Center(
                    child: Lottie.asset(ImageAssest.server,
                        width: 100, height: 100),
                  )
                : widget;
  }
}
