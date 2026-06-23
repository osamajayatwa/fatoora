import 'package:fatoora/core/constant/color.dart';
import 'package:fatoora/core/constant/imageassests.dart';
import 'package:flutter/material.dart';

class AdminLoginWaveHeader extends StatelessWidget {
  const AdminLoginWaveHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = (media.size.height * 0.32).clamp(220.0, 320.0);

    return ClipPath(
      clipper: const AdminLoginWaveClipper(),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColor.primaryDark,
              AppColor.primaryColor,
              AppColor.secondaryColor,
            ],
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 42),
        child: Image.asset(
          ImageAssest.logo,
          width: 210,
          height: 170,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class AdminLoginWaveClipper extends CustomClipper<Path> {
  const AdminLoginWaveClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..lineTo(0, size.height - 42)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height,
        size.width * 0.52,
        size.height - 34,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height - 72,
        size.width,
        size.height - 24,
      )
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
