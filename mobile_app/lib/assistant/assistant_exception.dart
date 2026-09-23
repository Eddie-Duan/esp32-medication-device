/// A user-facing error; never display upstream payloads, URLs or credentials.
class AssistantException implements Exception {
  const AssistantException(this.message);
  final String message;

  @override
  String toString() => message;
}
