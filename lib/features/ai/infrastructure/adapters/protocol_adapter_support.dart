import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';

Uri resolveAiEndpoint(
  AiProviderConnection connection,
  AiEndpointKind kind,
  String relativePath,
) {
  final override = connection.endpointOverrides[kind];
  if (override != null) return override;
  final path = connection.baseUri.path.endsWith('/')
      ? connection.baseUri.path
      : '${connection.baseUri.path}/';
  return connection.baseUri.replace(path: path).resolve(relativePath);
}

Uri applyAiAuthentication({
  required Uri endpoint,
  required Map<String, String> headers,
  required AiAdapterContext context,
}) {
  final apiKey = context.apiKey;
  if (apiKey == null || apiKey.isEmpty) return endpoint;
  switch (context.provider.authScheme) {
    case AiAuthScheme.bearer || AiAuthScheme.oauth:
      headers['Authorization'] = 'Bearer $apiKey';
    case AiAuthScheme.apiKeyHeader:
      headers[context.provider.authParameterName ?? 'x-api-key'] = apiKey;
    case AiAuthScheme.queryParameter:
      return endpoint.replace(
        queryParameters: {
          ...endpoint.queryParameters,
          context.provider.authParameterName ?? 'key': apiKey,
        },
      );
    case AiAuthScheme.none:
      break;
  }
  return endpoint;
}

String aiTextContent(AiMessage message) =>
    message.parts.whereType<AiTextPart>().map((part) => part.text).join();

int? aiIntValue(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text),
  _ => null,
};

/// Extracts provider text from JSON error envelopes, including gateways that
/// return HTTP 200 with an embedded error object.
String? aiErrorDetail(Map<String, Object?> payload) {
  final error = payload['error'];
  if (error is Map) {
    final map = Map<String, Object?>.from(error);
    for (final key in const ['message', 'detail', 'error']) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  for (final key in const ['detail', 'message', 'error']) {
    final value = payload[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  final nestedResponse = payload['response'];
  if (nestedResponse is Map) {
    return aiErrorDetail(Map<String, Object?>.from(nestedResponse));
  }
  return null;
}

AiFailure aiProviderPayloadFailure(Map<String, Object?> payload) {
  return AiFailure(
    code: AiFailureCode.serverFailure,
    messageKey: aiErrorDetail(payload) ?? 'ai.error.serverFailure',
  );
}

bool aiPayloadIsError(Map<String, Object?> payload) {
  if (payload['error'] != null) return true;
  final status = payload['status']?.toString().toLowerCase();
  return status == 'error' || status == 'failed' || status == 'failure';
}
