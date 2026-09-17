import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/motion/fatoora_motion_widgets.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:flutter/material.dart';

class AdminGoogleSignInButton extends StatelessWidget {
  const AdminGoogleSignInButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColor.surface,
          foregroundColor: AppColor.darkGrey,
          side: const BorderSide(color: AppColor.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox.square(
                dimension: 22,
                child: FatooraProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColor.primaryColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColor.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.asset(
                      ImageAssest.googleLogo,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
