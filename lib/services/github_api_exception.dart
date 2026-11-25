class GitHubApiException implements Exception {
  GitHubApiException(this.statusCode, this.message, {this.endpoint});

  final int statusCode;
  final String message;
  final String? endpoint;

  @override
  String toString() {
    final buffer = StringBuffer('GitHubApiException[HTTP $statusCode]');
    if (endpoint != null) buffer.write(' $endpoint');
    buffer.write(': $message');
    return buffer.toString();
  }
}
