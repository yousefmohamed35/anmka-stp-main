import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/design/app_colors.dart';
import '../../core/navigation/route_names.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';

/// Shown after registration when the account exists but email is not verified yet.
class VerifyEmailPendingScreen extends StatefulWidget {
  const VerifyEmailPendingScreen({
    super.key,
    required this.email,
  });

  final String email;

  @override
  State<VerifyEmailPendingScreen> createState() =>
      _VerifyEmailPendingScreenState();
}

class _VerifyEmailPendingScreenState extends State<VerifyEmailPendingScreen> {
  bool _resendLoading = false;

  Future<void> _resend() async {
    if (widget.email.trim().isEmpty) return;
    setState(() => _resendLoading = true);
    try {
      await AuthService.instance.resendVerificationEmail(
        email: widget.email.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.resendVerificationSuccess,
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _resendLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.beige,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.go(RouteNames.login),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l10n.verifyEmailTitle,
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.beige,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      size: 56,
                      color: AppColors.purple.withOpacity(0.9),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.verifyEmailHeadline,
                      style: GoogleFonts.cairo(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.verifyEmailBody(widget.email),
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        height: 1.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _resendLoading || widget.email.trim().isEmpty
                            ? null
                            : _resend,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.purple,
                          side: const BorderSide(color: AppColors.purple),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _resendLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.purple,
                                ),
                              )
                            : Text(
                                l10n.resendVerificationEmail,
                                style: GoogleFonts.cairo(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => context.go(RouteNames.login),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.purple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          l10n.backToLogin,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
