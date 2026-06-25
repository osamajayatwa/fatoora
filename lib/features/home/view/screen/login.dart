import 'package:fatoora/features/home/controllers/auth/login_controller.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/constants/color.dart';
import 'package:fatoora/core/constants/imageassests.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(LoginControllerImp());
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    return Scaffold(
      backgroundColor: AppColor.background,
      body: SafeArea(
        bottom: false,
        child: GetBuilder<LoginControllerImp>(
          builder: (controller) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 🌊 Wave Header with Logo inside
                  const WaveHeader(),

                  const SizedBox(height: 40),

                  // 🔹 Welcome Header
                  const AuthHeader(),

                  const SizedBox(height: 35),

                  // 🧾 Login Form
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 60.0 : 24.0,
                    ),
                    child: LoginForm(controller: controller),
                  ),

                  const SizedBox(height: 30),

                  // 🔹 Footer (Social Buttons)
                  // const AuthFooter(),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class WaveHeader extends StatelessWidget {
  const WaveHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return ClipPath(
      clipper: WaveClipper(),
      child: Container(
        width: double.infinity,
        height: size.height * 0.40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColor.primaryColor,
              AppColor.secondaryColor,
              AppColor.primaryColor,
            ],
          ),
        ),
        child: Center(
          child: Image.asset(
            ImageAssest.logo,
            width:
                size.width * 0.65, // 🔹 scales proportionally to screen width
            height: size.width * 0.60,
            fit: BoxFit.fill,
          ),
        ),
      ),
    );
  }
}

// 🌀 Custom Clipper for Wave
class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 50);
    path.quadraticBezierTo(
      size.width / 4,
      size.height,
      size.width / 2,
      size.height - 40,
    );
    path.quadraticBezierTo(
      size.width * 3 / 4,
      size.height - 90,
      size.width,
      size.height - 20,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// 🟥 Header Text (Below Wave)
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Sign in to continue',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColor.primaryColor,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Please enter your credentials below as driver',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColor.grey),
        ),
      ],
    );
  }
}

// 🧾 LOGIN FORM
class LoginForm extends StatelessWidget {
  final LoginControllerImp controller;
  const LoginForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Form(
      child: Column(
        children: [
          // Username
          CustomTextField(
            controller: controller.username,
            label: 'Username',
            hint: 'Enter your username',
            icon: Icons.person_outline,
            validator: (val) => val!.isEmpty ? 'Please enter username' : null,
          ),
          const SizedBox(height: 18),

          // Password
          GetBuilder<LoginControllerImp>(
            builder: (_) => CustomTextField(
              controller: controller.password,
              label: 'Password',
              hint: 'Enter your password',
              icon: Icons.lock_outline,
              obscureText: controller.isshowpassword,
              suffixIcon: IconButton(
                icon: Icon(
                  controller.isshowpassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColor.grey,
                ),
                onPressed: controller.showPassword,
              ),
              validator: (val) => val!.isEmpty ? 'Please enter password' : null,
            ),
          ),
          const SizedBox(height: 20),

          // 🔘 Login Button
          GradientButton(
            text: 'Login',
            onPressed: controller.fakeLogin,
            isLoading: controller.statusRequest == StatusRequest.loading,
          ),
        ],
      ),
    );
  }
}

// ✏️ Custom TextField Widget
class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        prefixIcon: Icon(icon, color: AppColor.primaryColor),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: BorderSide(
            color: AppColor.primaryColor.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: BorderSide(color: AppColor.secondaryColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: BorderSide(color: AppColor.primaryColor, width: 1.5),
        ),
      ),
    );
  }
}

// 🔘 Gradient Login Button
class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFB7212E), // اللون الأول
              Color(0xFFFA3C5A), // اللون الثاني
            ],
          ),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2), // سمك الإطار
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColor.background, // لون خلفية الزر
              borderRadius: BorderRadius.circular(23),
            ),
            child: ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColor.primaryColor,
                      ),
                    )
                  : Text(
                      text,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColor.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// 🌐 Social Footer
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Or continue with',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColor.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SocialAuthButton(
              icon: Icons.g_mobiledata_rounded,
              color: Colors.red,
            ),
            SizedBox(width: 16),
            SocialAuthButton(icon: Icons.apple, color: Colors.black),
            SizedBox(width: 16),
            SocialAuthButton(icon: Icons.facebook, color: Colors.blue),
          ],
        ),
      ],
    );
  }
}

class SocialAuthButton extends StatelessWidget {
  final IconData icon;
  final Color color;

  const SocialAuthButton({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      radius: 25,
      child: Icon(icon, color: color, size: 28),
    );
  }
}
