/// Thrown after registration when the account exists but email is not verified yet.
/// The app should route to the "check your email" screen (no tokens stored).
class EmailVerificationRequiredException implements Exception {
  EmailVerificationRequiredException({
    required this.email,
    this.serverMessage,
  });

  final String email;
  final String? serverMessage;

  @override
  String toString() =>
      serverMessage ?? 'Please verify your email before signing in.';
}

/// Thrown when login is rejected because the email is not verified.
class EmailNotVerifiedException implements Exception {
  EmailNotVerifiedException(this.message);

  final String message;

  @override
  String toString() => message;
}
