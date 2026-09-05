import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:JsxposedX/features/ai/domain/events/ai_stream_event.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/openai_chat_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/transport/sse_decoder.dart';

void main() {
  group('AiSseDecoder', () {
    test(
      'joins fields and survives arbitrary UTF-8 chunk boundaries',
      () async {
        final source = 'event: message\ndata: 你好\ndata: world\n\n';
        final bytes = utf8.encode(source);
        final chunks = <List<int>>[];
        for (var index = 0; index < bytes.length; index += 2) {
          chunks.add(bytes.sublist(index, (index + 2).clamp(0, bytes.length)));
        }

        final events = await const AiSseDecoder()
            .decode(Stream.fromIterable(chunks))
            .toList();

        expect(events, hasLength(1));
        expect(events.single.event, 'message');
        expect(events.single.data, '你好\nworld');
      },
    );

    test('rejects an oversized event', () async {
      expect(
        () => const AiSseDecoder(
          maxEventBytes: 4,
        ).decode(Stream.value(utf8.encode('data: 12345\n\n'))).toList(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('OpenAiChatAdapter', () {
    const adapter = OpenAiChatAdapter();

    test('emits deltas before the stream completes', () async {
      final first = jsonEncode({
        'choices': [
          {
            'delta': {'role': 'assistant', 'content': '你'},
            'finish_reason': null,
          },
        ],
      });
      final second = jsonEncode({
        'choices': [
          {
            'delta': {'content': '好'},
            'finish_reason': null,
          },
        ],
      });
      final events = adapter
          .decodeStream(
            Stream.fromIterable([
              utf8.encode('data: $first\n\n'),
              utf8.encode('data: $second\n\n'),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            requestId: 'r1',
          )
          .toList();

      final values = await events;
      expect(values.whereType<AiTextDelta>().map((event) => event.delta), [
        '你',
        '好',
      ]);
      expect(values.whereType<AiResponseCompleted>(), hasLength(1));
      expect(
        values.map((event) => event.sequence).toList(),
        orderedEquals([0, 1, 2, 3]),
      );
    });

    test('keeps usage and tool call deltas typed', () async {
      final chunk = jsonEncode({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call-1',
                  'function': {'name': 'search', 'arguments': '{"q":"x"}'},
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
        'usage': {
          'prompt_tokens': 2,
          'completion_tokens': 3,
          'total_tokens': 5,
        },
      });

      final values = await adapter
          .decodeStream(
            Stream.value(utf8.encode('data: $chunk\n\ndata: [DONE]\n\n')),
            requestId: 'r2',
          )
          .toList();

      final tool = values.whereType<AiToolCallDelta>().single;
      expect(tool.index, 0);
      expect(tool.toolCallId, 'call-1');
      expect(values.whereType<AiUsageUpdated>().single.value.totalTokens, 5);
      expect(
        values.whereType<AiResponseCompleted>().single.reason,
        AiFinishReason.toolCall,
      );
    });

    test(
      'prepares an OpenAI request using resolved secret and explicit endpoint',
      () {
        final connection = AiProviderConnection(
          id: 'c1',
          providerId: 'openai',
          displayName: 'Test',
          baseUri: Uri.parse('https://example.test/v1/'),
          endpointOverrides: {
            AiEndpointKind.chatCompletions: Uri.parse(
              'https://proxy.test/custom/chat',
            ),
          },
        );
        final request = AiRequest(
          requestId: 'r3',
          connection: connection,
          model: AiModelDefinition(
            id: 'model-1',
            connectionId: 'c1',
            displayName: 'Model',
            capabilities: const AiModelCapabilities(streaming: true),
            limits: const AiModelLimits(),
          ),
          messages: [
            AiMessage(
              id: 'm1',
              conversationId: 'conversation-1',
              role: AiMessageRole.user,
              parts: [AiContentPart.text('hello')],
              createdAt: _epoch,
            ),
          ],
        );

        final prepared = adapter.prepare(
          request,
          context: const AiAdapterContext(
            provider: AiProviderDefinition(
              id: 'openai',
              displayName: 'OpenAI',
              adapterId: 'openai.chat.v1',
            ),
            apiKey: 'secret',
          ),
        );
        expect(prepared.uri.toString(), 'https://proxy.test/custom/chat');
        expect(prepared.headers['Authorization'], 'Bearer secret');
        expect(prepared.body['model'], 'model-1');
        expect(prepared.body['messages'], isA<List<Object?>>());
      },
    );
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
