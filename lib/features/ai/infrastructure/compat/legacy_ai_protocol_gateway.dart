import 'dart:async';
import 'dart:convert';

import 'package:JsxposedX/core/enums/ai_api_type.dart';
import 'package:JsxposedX/core/models/ai_config.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_chat_orchestrator.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_stream_snapshot.dart';
import 'package:JsxposedX/features/ai/data/models/ai_message_dto.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart'
    as standard;
import 'package:JsxposedX/features/ai/domain/ports/ai_credential_store.dart';
import 'package:JsxposedX/features/ai/domain/registries/protocol_adapter_registry.dart';
import 'package:JsxposedX/features/ai/domain/registries/provider_definition_registry.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/anthropic_messages_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/openai_chat_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/openai_responses_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/transport/dio_ai_transport.dart';
import 'package:dio/dio.dart';

/// Bridges the legacy UI/runtime models to the standard protocol pipeline.
/// The legacy widgets keep their existing API; networking is delegated to the
/// protocol registry, transport and SSE adapters used by the new AI core.
class LegacyAiProtocolGateway {
  LegacyAiProtocolGateway(Dio dio)
    : _orchestrator = AiChatOrchestrator(
        providerRegistry: ProviderDefinitionRegistry(const [
          standard.AiProviderDefinition(
            id: 'openai',
            displayName: 'OpenAI Compatible',
            adapterId: 'openai.chat.v1',
          ),
          standard.AiProviderDefinition(
            id: 'openai-responses',
            displayName: 'OpenAI Responses',
            adapterId: 'openai.responses.v1',
          ),
          standard.AiProviderDefinition(
            id: 'anthropic',
            displayName: 'Anthropic',
            adapterId: 'anthropic.messages.v1',
            authScheme: standard.AiAuthScheme.apiKeyHeader,
            authParameterName: 'x-api-key',
          ),
        ]),
        adapterRegistry: ProtocolAdapterRegistry(const [
          OpenAiChatAdapter(),
          OpenAiResponsesAdapter(),
          AnthropicMessagesAdapter(),
        ]),
        transport: DioAiTransport(dio),
        credentialStore: const _EphemeralCredentialStore(),
      );

  final AiChatOrchestrator _orchestrator;

  Future<String> testConnection(AiConfig config) async {
    final stopwatch = Stopwatch()..start();
    final endpoint = Uri.parse(config.fullApiUrl);
    final connection = _connectionFor(config, endpoint);
    final model = _modelFor(config, connection);
    final credentialRef = connection.credentialRef!;
    _orchestratorCredentialStore.set(credentialRef, config.apiKey);
    final run = _orchestrator.start(
      standard.AiRequest(
        requestId: '${config.id}-test-${DateTime.now().microsecondsSinceEpoch}',
        connection: connection,
        model: model,
        messages: [
          standard.AiMessage(
            id: 'connection-test-message',
            conversationId: 'connection-test',
            role: standard.AiMessageRole.user,
            parts: const [standard.AiContentPart.text('Hi')],
            createdAt: DateTime.now().toUtc(),
          ),
        ],
        // Validate the same streaming protocol used by real conversations
        // without forcing generation parameters unsupported by some models.
        options: const standard.AiGenerationOptions(stream: true),
      ),
    );
    final snapshot = await run.completed;
    stopwatch.stop();
    if (snapshot.status == AiStreamStatus.failed) {
      throw StateError(snapshot.failure?.messageKey ?? 'Connection failed');
    }
    final elapsed = stopwatch.elapsedMilliseconds;
    return elapsed < 6000
        ? 'Connection successful (${elapsed}ms)'
        : 'Connection successful but latency is high (${elapsed}ms)';
  }

  Stream<AiMessageDto> stream({
    required AiConfig config,
    required List<AiMessageDto> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  }) async* {
    final requestId = '${config.id}-${DateTime.now().microsecondsSinceEpoch}';
    var attemptConfig = config;
    for (var attempt = 0; attempt < 2; attempt++) {
      final endpoint = Uri.parse(attemptConfig.fullApiUrl);
      final connection = _connectionFor(attemptConfig, endpoint);
      final model = _modelFor(attemptConfig, connection);
      final request = _requestFor(
        requestId: requestId,
        config: attemptConfig,
        connection: connection,
        model: model,
        messages: messages,
        tools: tools,
      );
      final store = _orchestratorCredentialStore;
      store.set(connection.credentialRef!, attemptConfig.apiKey);
      final run = _orchestrator.start(request);
      if (cancelToken != null) {
        unawaited(cancelToken.whenCancel.then((_) => run.cancel()));
      }

      var textLength = 0;
      var reasoningLength = 0;
      var emittedTools = false;
      var fallbackToChat = false;
      await for (final snapshot in run.snapshots) {
        if (snapshot.status == AiStreamStatus.failed) {
          fallbackToChat =
              attempt == 0 &&
              _canFallbackResponses(attemptConfig, snapshot.failure);
          if (fallbackToChat) break;
          throw StateError(snapshot.failure?.messageKey ?? 'AI request failed');
        }
        final text = snapshot.text;
        if (text.length > textLength) {
          yield AiMessageDto(
            role: 'assistant',
            content: text.substring(textLength),
          );
          textLength = text.length;
        }
        final reasoning = snapshot.reasoning;
        if (reasoning.length > reasoningLength) {
          yield AiMessageDto(
            role: 'assistant',
            content: reasoning.substring(reasoningLength),
            isThinking: true,
          );
          reasoningLength = reasoning.length;
        }
        if (!emittedTools &&
            snapshot.status == AiStreamStatus.completed &&
            snapshot.toolCalls.isNotEmpty) {
          emittedTools = true;
          yield AiMessageDto.assistantToolCalls(
            snapshot.toolCalls
                .map(
                  (call) => {
                    'id': call.id,
                    'type': 'function',
                    'function': {
                      'name': call.name,
                      'arguments': call.argumentsJson,
                    },
                  },
                )
                .toList(growable: false),
          );
        }
      }
      if (!fallbackToChat) return;
      attemptConfig = config.copyWith(apiType: AiApiType.openai);
    }
  }

  standard.AiRequest _requestFor({
    required String requestId,
    required AiConfig config,
    required standard.AiProviderConnection connection,
    required standard.AiModelDefinition model,
    required List<AiMessageDto> messages,
    List<Map<String, dynamic>>? tools,
  }) {
    return standard.AiRequest(
      requestId: requestId,
      connection: connection,
      model: model,
      messages: messages.map(_toStandardMessage).toList(growable: false),
      options: standard.AiGenerationOptions(
        maxOutputTokens: config.maxToken > 0 ? config.maxToken : null,
        temperature: config.temperature >= 0 ? config.temperature : null,
        stream: true,
      ),
      tools: _toStandardTools(tools),
    );
  }

  static bool _canFallbackResponses(
    AiConfig config,
    standard.AiFailure? failure,
  ) {
    return config.apiType == AiApiType.openaiResponses &&
        (failure?.httpStatus == 404 || failure?.httpStatus == 405);
  }

  standard.AiProviderConnection _connectionFor(AiConfig config, Uri endpoint) {
    final credentialRef = 'legacy-runtime-${config.id}';
    final kind = _endpointKind(config.apiType);
    return standard.AiProviderConnection(
      id: 'legacy-runtime-connection-${config.id}',
      providerId: _providerId(config.apiType),
      displayName: config.name,
      baseUri: endpoint.replace(path: '/', query: null, fragment: null),
      credentialRef: credentialRef,
      endpointOverrides: {kind: endpoint},
    );
  }

  standard.AiModelDefinition _modelFor(
    AiConfig config,
    standard.AiProviderConnection connection,
  ) {
    return standard.AiModelDefinition(
      id: config.moduleName,
      connectionId: connection.id,
      displayName: config.moduleName,
      capabilities: const standard.AiModelCapabilities(
        streaming: true,
        toolCalling: true,
      ),
      limits: standard.AiModelLimits(
        maxOutputTokens: config.maxToken > 0 ? config.maxToken : null,
      ),
      source: 'legacy-runtime',
    );
  }

  static standard.AiMessage _toStandardMessage(AiMessageDto message) {
    final role = switch (message.role) {
      'system' => standard.AiMessageRole.system,
      'assistant' => standard.AiMessageRole.assistant,
      'tool' => standard.AiMessageRole.tool,
      _ => standard.AiMessageRole.user,
    };
    final parts = <standard.AiContentPart>[];
    if (message.content.isNotEmpty) {
      parts.add(standard.AiContentPart.text(message.content));
    }
    if (message.reasoningContent?.isNotEmpty == true) {
      parts.add(standard.AiContentPart.reasoning(message.reasoningContent!));
    }
    for (final rawCall in message.toolCalls ?? const <Map<String, dynamic>>[]) {
      final function = rawCall['function'];
      final functionMap = function is Map
          ? Map<String, dynamic>.from(function)
          : const <String, dynamic>{};
      final rawArguments = functionMap['arguments'];
      final arguments = rawArguments is String
          ? _decodeArguments(rawArguments)
          : (rawArguments is Map
                ? Map<String, Object?>.from(rawArguments)
                : const <String, Object?>{});
      parts.add(
        standard.AiContentPart.toolCall(
          toolCall: standard.AiToolCall(
            id: rawCall['id']?.toString() ?? 'legacy-tool-call',
            name: functionMap['name']?.toString() ?? '',
            arguments: arguments,
          ),
        ),
      );
    }
    if (message.role == 'tool') {
      parts.add(
        standard.AiContentPart.toolResult(
          toolResult: standard.AiToolResult(
            toolCallId: message.toolCallId ?? '',
            name: 'tool',
            success: !message.isError,
            content: message.content,
          ),
        ),
      );
    }
    return standard.AiMessage(
      id: message.id ?? 'legacy-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: 'legacy-runtime',
      role: role,
      parts: parts,
      createdAt: DateTime.now().toUtc(),
    );
  }

  static List<standard.AiToolSpec> _toStandardTools(
    List<Map<String, dynamic>>? tools,
  ) {
    if (tools == null) return const [];
    return tools
        .map((raw) {
          final function = raw['function'];
          if (function is Map) {
            final map = Map<String, dynamic>.from(function);
            return standard.AiToolSpec(
              name: map['name']?.toString() ?? '',
              description: map['description']?.toString() ?? '',
              inputSchema: Map<String, Object?>.from(
                (map['parameters'] as Map?) ?? const {},
              ),
            );
          }
          return standard.AiToolSpec(
            name: raw['name']?.toString() ?? '',
            description: raw['description']?.toString() ?? '',
            inputSchema: Map<String, Object?>.from(
              (raw['input_schema'] as Map?) ?? const {},
            ),
          );
        })
        .where((tool) => tool.name.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, Object?> _decodeArguments(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  static String _providerId(AiApiType type) => switch (type) {
    AiApiType.openai => 'openai',
    AiApiType.openaiResponses => 'openai-responses',
    AiApiType.anthropic => 'anthropic',
  };

  static standard.AiEndpointKind _endpointKind(AiApiType type) =>
      switch (type) {
        AiApiType.openai => standard.AiEndpointKind.chatCompletions,
        AiApiType.openaiResponses => standard.AiEndpointKind.responses,
        AiApiType.anthropic => standard.AiEndpointKind.messages,
      };

  static final _orchestratorCredentialStore = _EphemeralCredentialStore();
}

class _EphemeralCredentialStore implements AiCredentialStore {
  const _EphemeralCredentialStore();

  static final Map<String, String> _values = <String, String>{};

  void set(String reference, String value) => _values[reference] = value;

  @override
  Future<String> put(AiSecret secret, {String? credentialRef}) async {
    final reference = credentialRef ?? 'legacy-runtime';
    _values[reference] = secret.value;
    return reference;
  }

  @override
  Future<AiSecret?> read(String credentialRef) async {
    final value = _values[credentialRef];
    return value == null ? null : AiSecret(value);
  }

  @override
  Future<void> delete(String credentialRef) async =>
      _values.remove(credentialRef);
}
