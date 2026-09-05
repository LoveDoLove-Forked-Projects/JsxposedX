import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:JsxposedX/features/ai/domain/events/ai_stream_event.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/anthropic_messages_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/openai_chat_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/openai_responses_adapter.dart';

void main() {
  test(
    'keeps provider detail from an embedded OpenAI error envelope',
    () async {
      final events = await const OpenAiChatAdapter()
          .decodeResponse(
            utf8.encode(
              jsonEncode({
                'error': {'message': '模型暂不支持该接口'},
              }),
            ),
            requestId: 'request-1',
          )
          .toList();

      final failure = events.whereType<AiResponseFailed>().single.failure;
      expect(failure.code, AiFailureCode.serverFailure);
      expect(failure.messageKey, '模型暂不支持该接口');
    },
  );

  test('keeps error detail from an OpenAI Responses failure event', () async {
    final payload = jsonEncode({
      'type': 'response.failed',
      'response': {
        'error': {'message': 'Responses 被网关拒绝'},
      },
    });
    final events = await const OpenAiResponsesAdapter()
        .decodeStream(
          Stream.value(
            utf8.encode('event: response.failed\ndata: $payload\n\n'),
          ),
          requestId: 'request-1',
        )
        .toList();

    final failure = events.whereType<AiResponseFailed>().single.failure;
    expect(failure.code, AiFailureCode.serverFailure);
    expect(failure.messageKey, 'Responses 被网关拒绝');
  });

  group('OpenAiResponsesAdapter', () {
    const adapter = OpenAiResponsesAdapter();

    test('decodes text, reasoning, usage and completion events', () async {
      final events = [
        {
          'type': 'response.reasoning_summary_text.delta',
          'item_id': 'r',
          'delta': 'think',
        },
        {
          'type': 'response.output_text.delta',
          'item_id': 'o',
          'delta': 'answer',
        },
        {
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'usage': {'input_tokens': 2, 'output_tokens': 4, 'total_tokens': 6},
          },
        },
      ];
      final stream = Stream<List<int>>.fromIterable(
        events.map((event) => utf8.encode('data: ${jsonEncode(event)}\n\n')),
      );

      final values = await adapter
          .decodeStream(stream, requestId: 'responses')
          .toList();

      expect(values.whereType<AiReasoningDelta>().single.delta, 'think');
      expect(values.whereType<AiTextDelta>().single.delta, 'answer');
      expect(values.whereType<AiUsageUpdated>().single.value.totalTokens, 6);
      expect(values.whereType<AiResponseCompleted>(), hasLength(1));
    });

    test('uses Responses request shape', () {
      final prepared = adapter.prepare(
        _request(providerId: 'openai-responses'),
        context: const AiAdapterContext(
          provider: AiProviderDefinition(
            id: 'openai-responses',
            displayName: 'Responses',
            adapterId: 'openai.responses.v1',
          ),
          apiKey: 'secret',
        ),
      );

      expect(prepared.uri.path, '/v1/responses');
      expect(prepared.body, contains('input'));
      expect(prepared.body, isNot(contains('messages')));
    });

    test('uses output_text for assistant history items', () {
      final request = _request(providerId: 'openai-responses').copyWith(
        messages: [
          ..._request(providerId: 'openai-responses').messages,
          AiMessage(
            id: 'assistant',
            conversationId: 'conversation',
            role: AiMessageRole.assistant,
            parts: [AiContentPart.text('previous answer')],
            createdAt: _epoch,
          ),
        ],
      );
      final prepared = adapter.prepare(
        request,
        context: const AiAdapterContext(
          provider: AiProviderDefinition(
            id: 'openai-responses',
            displayName: 'Responses',
            adapterId: 'openai.responses.v1',
          ),
          apiKey: 'secret',
        ),
      );

      final input = (prepared.body['input'] as List).last as Map;
      expect(input['role'], 'assistant');
      expect((input['content'] as List).single['type'], 'output_text');
    });
  });

  group('AnthropicMessagesAdapter', () {
    const adapter = AnthropicMessagesAdapter();

    test('decodes content and partial tool JSON', () async {
      final records = [
        (
          'content_block_start',
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'tool_use',
              'id': 'call-1',
              'name': 'scan',
            },
          },
        ),
        (
          'content_block_delta',
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"path":"x"}',
            },
          },
        ),
        (
          'content_block_delta',
          {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'text_delta', 'text': 'done'},
          },
        ),
        (
          'message_delta',
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 8},
          },
        ),
      ];
      final stream = Stream<List<int>>.fromIterable(
        records.map(
          (record) => utf8.encode(
            'event: ${record.$1}\ndata: ${jsonEncode(record.$2)}\n\n',
          ),
        ),
      );

      final values = await adapter
          .decodeStream(stream, requestId: 'anthropic')
          .toList();

      final toolDeltas = values.whereType<AiToolCallDelta>().toList();
      expect(toolDeltas.first.toolCallId, 'call-1');
      expect(toolDeltas.last.argumentsDelta, '{"path":"x"}');
      expect(values.whereType<AiTextDelta>().single.delta, 'done');
      expect(
        values.whereType<AiResponseCompleted>().single.reason,
        AiFinishReason.toolCall,
      );
    });

    test('extracts system message and uses Anthropic headers', () {
      final prepared = adapter.prepare(
        _request(providerId: 'anthropic', includeSystem: true),
        context: const AiAdapterContext(
          provider: AiProviderDefinition(
            id: 'anthropic',
            displayName: 'Anthropic',
            adapterId: 'anthropic.messages.v1',
            authScheme: AiAuthScheme.apiKeyHeader,
            authParameterName: 'x-api-key',
          ),
          apiKey: 'secret',
        ),
      );

      expect(prepared.uri.path, '/v1/messages');
      expect(prepared.headers['x-api-key'], 'secret');
      expect(prepared.headers['anthropic-version'], '2023-06-01');
      expect(prepared.body['system'], 'be precise');
      expect(prepared.body['messages'], hasLength(1));
    });
  });
}

AiRequest _request({required String providerId, bool includeSystem = false}) {
  return AiRequest(
    requestId: 'request',
    connection: AiProviderConnection(
      id: 'connection',
      providerId: providerId,
      displayName: providerId,
      baseUri: Uri.parse('https://example.test/v1/'),
    ),
    model: const AiModelDefinition(
      id: 'model',
      connectionId: 'connection',
      displayName: 'Model',
      capabilities: AiModelCapabilities(streaming: true, toolCalling: true),
      limits: AiModelLimits(maxOutputTokens: 1024),
    ),
    messages: [
      if (includeSystem)
        AiMessage(
          id: 'system',
          conversationId: 'conversation',
          role: AiMessageRole.system,
          parts: [AiContentPart.text('be precise')],
          createdAt: _epoch,
        ),
      AiMessage(
        id: 'user',
        conversationId: 'conversation',
        role: AiMessageRole.user,
        parts: [AiContentPart.text('hello')],
        createdAt: _epoch,
      ),
    ],
  );
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
