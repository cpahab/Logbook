/// Simple message-carrying failure type. Currently unused — no code
/// constructs a [Failure] yet; repositories/services surface errors via
/// thrown exceptions instead.
class Failure {
  final String message;
  Failure(this.message);
}
