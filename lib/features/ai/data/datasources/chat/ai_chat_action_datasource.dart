import 'dart:convert';

import 'package:JsxposedX/core/models/ai_config.dart';
import 'package:JsxposedX/core/networks/http_service.dart';
import 'package:JsxposedX/core/providers/pinia_provider.dart';
import 'package:JsxposedX/features/ai/data/models/ai_message_dto.dart';
import 'package:JsxposedX/features/ai/data/models/ai_session_dto.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_chat_session_context.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_multimodal_message_codec.dart';
import 'package:JsxposedX/features/ai/infrastructure/compat/legacy_ai_protocol_gateway.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const String openAiResponsesReasoningProtocolPrefix =
    '[responses_reasoning_item]';

class AiChatActionDatasource {
  AiChatActionDatasource({
    required HttpService httpService,
    required PiniaStorage storage,
  }) : _storage = storage,
       _standardGateway = LegacyAiProtocolGateway(httpService.dio);

  final PiniaStorage _storage;
  final LegacyAiProtocolGateway _standardGateway;

  static const String _sessionIndexKeyPrefix = 'ai_v2_sessions_';
  static const String _chatSpacePrefix = 'ai_v2_chat_';
  static const String _chatConfigSpacePrefix = 'ai_v2_chat_config_';
  static const String _chatContentKey = 'messages';
  static const String _chatContextKey = 'context';
  static const String _chatConfigKey = 'config';

  Stream<AiMessageDto> postChatStream({
    required AiConfig config,
    required List<AiMessageDto> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  }) {
    return _standardGateway.stream(
      config: config,
      messages: messages,
      tools: tools,
      cancelToken: cancelToken,
    );
  }

  Future<String> testConnection(AiConfig config) {
    return _standardGateway.testConnection(config);
  }

  Future<void> saveSessionsIndex(
    String packageName,
    List<AiSessionDto> sessionsDtos,
  ) async {
    final json = jsonEncode(sessionsDtos.map((e) => e.toJson()).toList());
    await _storage.setString(_getSessionIndexKey(packageName), json);
  }

  Future<void> saveLastActiveSessionId(
    String packageName,
    String sessionId,
  ) async {
    await _storage.setString(
      _chatConfigKey,
      sessionId,
      space: _getChatConfigSpace(packageName),
    );
  }

  Future<void> clearLastActiveSessionId(String packageName) async {
    await _storage.remove(
      _chatConfigKey,
      space: _getChatConfigSpace(packageName),
    );
  }

  Future<void> saveChatHistory(
    String packageName,
    String sessionId,
    List<AiMessageDto> messagesDtos,
  ) async {
    final json = jsonEncode(
      messagesDtos.map((e) => e.toStorageJson()).toList(),
    );
    await _storage.setString(
      _chatContentKey,
      json,
      space: _getChatSpace(sessionId, packageName),
    );
  }

  Future<void> saveSessionContext(
    String packageName,
    String sessionId,
    AiChatSessionContext context,
  ) async {
    await _storage.setString(
      _chatContextKey,
      jsonEncode(context.toStorageJson()),
      space: _getChatSpace(sessionId, packageName),
    );
  }

  Future<void> removeChatHistory(String packageName, String sessionId) async {
    await _storage.clear(space: _getChatSpace(sessionId, packageName));
  }

  String _getSessionIndexKey(String packageName) =>
      '$_sessionIndexKeyPrefix$packageName';

  String _getChatSpace(String sessionId, String packageName) =>
      '$_chatSpacePrefix${sessionId}_$packageName';

  String _getChatConfigSpace(String packageName) =>
      '$_chatConfigSpacePrefix$packageName';
}

@visibleForTesting
final class OpenAiResponsesPayloadComposer {
  static List<Map<String, dynamic>> buildInput(List<AiMessageDto> messages) {
    final input = <Map<String, dynamic>>[];

    for (final message in messages) {
      final reasoningItem = OpenAiResponsesReasoningItemCodec.tryDecode(
        message.content,
      );
      if (reasoningItem != null) {
        input.add(reasoningItem);
        continue;
      }

      if (message.role == 'system' || message.role == 'developer') {
        input.add({
          'type': 'message',
          'role': 'developer',
          'content': <Map<String, dynamic>>[
            {'type': 'input_text', 'text': message.content},
          ],
        });
        continue;
      }

      if (message.role == 'tool') {
        final toolCallId = message.toolCallId?.trim();
        if (toolCallId == null || toolCallId.isEmpty) {
          continue;
        }
        input.add({
          'type': 'function_call_output',
          'call_id': toolCallId,
          'output': message.content,
        });
        continue;
      }

      if (message.hasToolCalls) {
        if (message.content.trim().isNotEmpty) {
          input.add(mapMessage(message));
        }
        for (final toolCall in message.toolCalls!) {
          final function = toolCall['function'] as Map<String, dynamic>? ?? {};
          final callId = toolCall['id']?.toString().trim() ?? '';
          final name = function['name']?.toString().trim() ?? '';
          if (callId.isEmpty || name.isEmpty) {
            continue;
          }
          input.add({
            'type': 'function_call',
            'call_id': callId,
            'name': name,
            'arguments': function['arguments']?.toString() ?? '{}',
          });
        }
        continue;
      }

      input.add(mapMessage(message));
    }

    return input;
  }

  static Map<String, dynamic> mapMessage(AiMessageDto message) {
    final normalizedRole = message.role == 'assistant' ? 'assistant' : 'user';
    final contentType = normalizedRole == 'assistant'
        ? 'output_text'
        : 'input_text';
    if (normalizedRole == 'user' &&
        AiMultimodalMessageCodec.isEncoded(message.content)) {
      return {
        'type': 'message',
        'role': normalizedRole,
        'content': toResponsesContent(message.content),
      };
    }

    return {
      'type': 'message',
      'role': normalizedRole,
      'content': <Map<String, dynamic>>[
        {'type': contentType, 'text': message.content},
      ],
    };
  }

  static List<Map<String, dynamic>> toResponsesContent(String content) {
    final openAiContent = AiMultimodalMessageCodec.toOpenAiContent(
      content,
      isZh: true,
    );
    return openAiContent
        .map((part) {
          final type = part['type']?.toString() ?? 'text';
          switch (type) {
            case 'image_url':
              final imagePayload = part['image_url'];
              return {
                'type': 'input_image',
                'image_url': imagePayload is Map<String, dynamic>
                    ? imagePayload['url']?.toString() ?? ''
                    : '',
              };
            case 'text':
            default:
              return {
                'type': 'input_text',
                'text': part['text']?.toString() ?? '',
              };
          }
        })
        .toList(growable: false);
  }
}

final class OpenAiResponsesReasoningItemCodec {
  static String encode(Map<String, dynamic> item) {
    return '$openAiResponsesReasoningProtocolPrefix${jsonEncode(item)}';
  }

  static bool isEncoded(String content) {
    return content.startsWith(openAiResponsesReasoningProtocolPrefix);
  }

  static Map<String, dynamic>? tryDecode(String content) {
    if (!isEncoded(content)) {
      return null;
    }
    try {
      final raw = content.substring(
        openAiResponsesReasoningProtocolPrefix.length,
      );
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
