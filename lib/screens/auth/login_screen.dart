import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/design/app_colors.dart';
import '../../core/navigation/route_names.dart';
import '../../core/auth/email_verification_exceptions.dart';
import '../../services/auth_service.dart';
import '../../services/email_storage_service.dart';
import '../../l10n/app_localizations.dart';

/// Login Screen - Clean Design like Account Page
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailOrPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailStorageService = EmailStorageService();
  final _emailFocusNode = FocusNode();
  bool _showPassword = false;
  bool _isLoading = false;
  List<String> _savedEmails = [];
  // bool _googleLoading = false;
  // bool _appleLoading = false;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_onEmailFocusChanged);
    _loadSavedEmails();
  }

  void _onEmailFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadSavedEmails() async {
    final emails = await _emailStorageService.getSavedEmails();
    if (!mounted) return;
    setState(() {
      _savedEmails = emails;
    });
  }

  List<String> get _filteredEmails {
    final query = _emailOrPhoneController.text.trim().toLowerCase();
    if (query.isEmpty) return _savedEmails;
    return _savedEmails
        .where((email) => email.toLowerCase().contains(query))
        .toList();
  }

  void _selectSavedEmail(String email) {
    _emailOrPhoneController.text = email;
    _emailOrPhoneController.selection = TextSelection.fromPosition(
      TextPosition(offset: email.length),
    );
    FocusScope.of(context).requestFocus(_passwordFocusNode);
    setState(() {});
  }

  final _passwordFocusNode = FocusNode();

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final authResponse = await AuthService.instance.login(
          emailOrPhone: _emailOrPhoneController.text.trim(),
          password: _passwordController.text,
        );

        if (!mounted) return;

        await _emailStorageService.saveEmail(_emailOrPhoneController.text);
        await _loadSavedEmails();

        // Save launch flag
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hasLaunched', true);

        // Navigate by role: instructor → instructor flow, else → student flow
        if (mounted) {
          final role = authResponse.user.role.toLowerCase();
          if (role == 'instructor' || role == 'teacher') {
            context.go(RouteNames.instructorHome);
          } else {
            context.go(RouteNames.home);
          }
        }
      } on EmailNotVerifiedException catch (e) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        final msg = e.message.trim().isNotEmpty
            ? e.message
            : l10n.emailNotVerifiedLogin;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
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
            duration: const Duration(seconds: 3),
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  // Google and Apple auth - commented out
  // Future<void> _handleGoogleLogin() async {
  //   if (_googleLoading || _appleLoading) return;
  //   setState(() {
  //     _googleLoading = true;
  //     _appleLoading = false;
  //   });

  //   try {
  //     final authResponse = await AuthService.instance.signInWithGoogle();

  //     if (!mounted) return;

  //     final prefs = await SharedPreferences.getInstance();
  //     await prefs.setBool('hasLaunched', true);

  //     if (mounted) {
  //       final role = authResponse.user.role.toLowerCase();
  //       if (role == 'instructor' || role == 'teacher') {
  //         context.go(RouteNames.instructorHome);
  //       } else {
  //         context.go(RouteNames.home);
  //       }
  //     }
  //   } catch (e) {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text(
  //           e.toString().replaceFirst('Exception: ', ''),
  //           style: GoogleFonts.cairo(),
  //         ),
  //         backgroundColor: Colors.red,
  //         duration: const Duration(seconds: 3),
  //       ),
  //     );
  //   } finally {
  //     if (mounted) {
  //       setState(() => _googleLoading = false);
  //     }
  //   }
  // }

  // Future<void> _handleAppleLogin() async {
  //   if (_appleLoading || _googleLoading) return;
  //   setState(() {
  //     _appleLoading = true;
  //     _googleLoading = false;
  //   });

  //   try {
  //     final authResponse = await AuthService.instance.signInWithApple();

  //     if (!mounted) return;

  //     final prefs = await SharedPreferences.getInstance();
  //     await prefs.setBool('hasLaunched', true);

  //     if (mounted) {
  //       final role = authResponse.user.role.toLowerCase();
  //       if (role == 'instructor' || role == 'teacher') {
  //         context.go(RouteNames.instructorHome);
  //       } else {
  //         context.go(RouteNames.home);
  //       }
  //     }
  //   } catch (e) {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text(
  //           e.toString().replaceFirst('Exception: ', ''),
  //           style: GoogleFonts.cairo(),
  //         ),
  //         backgroundColor: Colors.red,
  //         duration: const Duration(seconds: 3),
  //       ),
  //     );
  //   } finally {
  //     if (mounted) {
  //       setState(() => _appleLoading = false);
  //     }
  //   }
  // }

  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    _emailFocusNode.removeListener(_onEmailFocusChanged);
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // Purple Header
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
                child: Column(
                  children: [
                    // Back Button
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.go(RouteNames.onboarding1),
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
                          AppLocalizations.of(context)!.login,
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
                    const SizedBox(height: 30),
                    // Logo
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/play_store_512.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.school_rounded,
                            size: 45,
                            color: AppColors.purple,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.welcomeBack,
                      style: GoogleFonts.cairo(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Form Container
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.beige,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Email or Phone Field
                          _buildLabel(
                              AppLocalizations.of(context)!.emailOrPhone),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _emailOrPhoneController,
                            hint:
                                AppLocalizations.of(context)!.enterEmailOrPhone,
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.text,
                            focusNode: _emailFocusNode,
                            autofillHints: const [AutofillHints.email],
                            onChanged: (_) => setState(() {}),
                          ),
                          _buildEmailSuggestions(),
                          const SizedBox(height: 20),

                          // Password Field
                          _buildLabel(AppLocalizations.of(context)!.password),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _passwordController,
                            hint: AppLocalizations.of(context)!.enterPassword,
                            icon: Icons.lock_outline_rounded,
                            isPassword: true,
                            focusNode: _passwordFocusNode,
                            autofillHints: const [AutofillHints.password],
                          ),
                          const SizedBox(height: 12),

                          // Forgot Password
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () =>
                                  context.push(RouteNames.forgotPassword),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                              ),
                              child: Text(
                                AppLocalizations.of(context)!.forgotPassword,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: AppColors.purple,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Login Button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.purple,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      AppLocalizations.of(context)!.login,
                                      style: GoogleFonts.cairo(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Apple and Google auth widget - commented out
                          // // Divider
                          // Row(
                          //   children: [
                          //     Expanded(child: Divider(color: Colors.grey[300])),
                          //     Padding(
                          //       padding:
                          //           const EdgeInsets.symmetric(horizontal: 16),
                          //       child: Text(
                          //         AppLocalizations.of(context)!.or,
                          //         style: GoogleFonts.cairo(
                          //             color: AppColors.mutedForeground),
                          //       ),
                          //     ),
                          //     Expanded(child: Divider(color: Colors.grey[300])),
                          //   ],
                          // ),
                          // const SizedBox(height: 24),

                          // // Social Buttons
                          // Row(
                          //   children: [
                          //     Expanded(
                          //         child: _buildSocialButton(
                          //       icon: Icons.g_mobiledata_rounded,
                          //       label: AppLocalizations.of(context)!.google,
                          //       onPressed: (_isLoading || _appleLoading)
                          //           ? null
                          //           : _handleGoogleLogin,
                          //       isLoading: _googleLoading,
                          //     )),
                          //     const SizedBox(width: 12),
                          //     Expanded(
                          //         child: _buildSocialButton(
                          //       icon: Icons.apple_rounded,
                          //       label: AppLocalizations.of(context)!.apple,
                          //       onPressed: (_isLoading || _googleLoading)
                          //           ? null
                          //           : _handleAppleLogin,
                          //       isLoading: _appleLoading,
                          //     )),
                          //   ],
                          // ),

                          const SizedBox(height: 32),

                          // Register Link
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.noAccount,
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    color: AppColors.mutedForeground,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      context.go(RouteNames.register),
                                  child: Text(
                                    AppLocalizations.of(context)!.registerNow,
                                    style: GoogleFonts.cairo(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.purple,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: _buildPoweredByFooter(),
          ),
        ],
      ),
    );
  }

  Widget _buildPoweredByFooter() {
    return Center(
      child: Text.rich(
        TextSpan(
          text: 'Powered by ',
          style: GoogleFonts.cairo(
            fontSize: 13,
            color: AppColors.mutedForeground,
            fontWeight: FontWeight.w500,
          ),
          children: [
            TextSpan(
              text: 'Anmka',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.cairo(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    List<String>? autofillHints,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isPassword && !_showPassword,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        onChanged: onChanged,
        style: GoogleFonts.cairo(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              GoogleFonts.cairo(color: AppColors.mutedForeground, fontSize: 14),
          prefixIcon: Icon(icon, color: AppColors.purple, size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.mutedForeground,
                    size: 22,
                  ),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return AppLocalizations.of(context)!.fieldRequired;
          }
          // Accept any input (email or phone) - validation will be done by backend
          return null;
        },
      ),
    );
  }

  Widget _buildEmailSuggestions() {
    final suggestions = _filteredEmails;
    if (!_emailFocusNode.hasFocus ||
        _savedEmails.isEmpty ||
        suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: suggestions.take(4).map((email) {
            return ListTile(
              dense: true,
              title: Text(
                email,
                style: GoogleFonts.cairo(fontSize: 14),
              ),
              onTap: () => _selectSavedEmail(email),
            );
          }).toList(),
        ),
      ),
    );
  }

  // /* Apple and Google auth widget - commented out
  // Widget _buildSocialButton({
  //   required IconData icon,
  //   required String label,
  //   VoidCallback? onPressed,
  //   bool isLoading = false,
  // }) {
  //   final isDisabled = onPressed == null || isLoading;
  //   return Opacity(
  //     opacity: isDisabled ? 0.6 : 1,
  //     child: InkWell(
  //       onTap: isDisabled ? null : onPressed,
  //       borderRadius: BorderRadius.circular(14),
  //       child: Container(
  //         height: 50,
  //         decoration: BoxDecoration(
  //           color: Colors.white,
  //           borderRadius: BorderRadius.circular(14),
  //           boxShadow: [
  //             BoxShadow(
  //               color: Colors.black.withOpacity(0.04),
  //               blurRadius: 10,
  //               offset: const Offset(0, 4),
  //             ),
  //           ],
  //         ),
  //         child: Row(
  //           mainAxisAlignment: MainAxisAlignment.center,
  //           children: [
  //             if (isLoading)
  //               const SizedBox(
  //                 width: 20,
  //                 height: 20,
  //                 child: CircularProgressIndicator(
  //                   strokeWidth: 2,
  //                   color: AppColors.purple,
  //                 ),
  //               )
  //             else
  //               Icon(icon, size: 24, color: AppColors.foreground),
  //             const SizedBox(width: 8),
  //             Text(
  //               label,
  //               style: GoogleFonts.cairo(
  //                 fontSize: 14,
  //                 fontWeight: FontWeight.w600,
  //                 color: AppColors.foreground,
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }
}
