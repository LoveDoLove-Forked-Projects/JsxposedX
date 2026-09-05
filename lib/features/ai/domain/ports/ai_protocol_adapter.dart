import 'package:JsxposedX/features/ai/domain/events/ai_stream_event.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';

abstract interface class AiProtocolAdapter {
  String get id;

  PreparedAiRequest prepare(
    AiRequest request, {
    required AiAdapterContext context,
  });

  Stream<AiStreamEvent> decodeStream(
    Stream<List<int>> bytes, {
    required String requestId,
  });

  Stream<AiStreamEvent> decodeResponse(
    List<int> bytes, {
    required String requestId,
  });
}

class AiAdapterContext {
  const AiAdapterContext({required this.provider, this.apiKey});

  final AiProviderDefinition provider;

  /// Resolved only for the duration of request preparation.
  final String? apiKey;
}

class PreparedAiRequest {
  const PreparedAiRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final Map<String, Object?> body;
}

abstract interface class AiTransport {
  Future<AiTransportResponse> send(
    PreparedAiRequest request, {
    required AiCancellationToken cancellation,
  });
}

class AiTransportResponse {
  const AiTransportResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final Stream<List<int>> body;
}

abstract interface class AiCancellationToken {
  bool get isCancelled;

  Future<void> get cancelled;
}

class AiTransportException implements Exception {
  const AiTransportException(this.failure);

  final AiFailure failure;

  @override
  String toString() => 'AiTransportException(${failure.code.name})';
}
