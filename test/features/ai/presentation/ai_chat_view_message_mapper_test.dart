import 'package:JsxposedX/features/ai/application/chat/ai_stream_snapshot.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/presentation/mappers/ai_chat_view_message_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AiChatViewMessageMapper();

  test('maps standard text and reasoning without a legacy message', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'assistant',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.reasoning('inspect first'),
          AiContentPart.text('answer'),
        ],
        createdAt: _epoch,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.id, 'assistant');
    expect(result.single.role, 'assistant');
    expect(result.single.content, contains('inspect first'));
    expect(result.single.content, contains('answer'));
  });

  test('maps ordinary user text to a user view message', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'user',
        conversationId: 'conversation',
        role: AiMessageRole.user,
        parts: const [AiContentPart.text('hello there')],
        createdAt: _epoch,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.id, 'user');
    expect(result.single.role, 'user');
    expect(result.single.content, 'hello there');
    expect(result.single.isError, isFalse);
    expect(result.single.isToolResultBubble, isFalse);
  });

  test('maps a complete tool exchange to one result view item', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'call-message',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-1',
              name: 'inspect_apk',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
      AiMessage(
        id: 'result-message',
        conversationId: 'conversation',
        role: AiMessageRole.tool,
        parts: const [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-1',
              name: 'inspect_apk',
              success: true,
              content: 'done',
            ),
          ),
        ],
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.isToolResultBubble, isTrue);
    expect(result.single.content, contains('inspect_apk'));
    expect(result.single.content, contains('done'));
  });

  test('keeps tool call and result paired when multiple calls are present', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'calls',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-a',
              name: 'first_tool',
              arguments: {},
            ),
          ),
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-b',
              name: 'second_tool',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
      AiMessage(
        id: 'results',
        conversationId: 'conversation',
        role: AiMessageRole.tool,
        parts: const [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-b',
              name: 'second_tool',
              success: true,
              content: 'second done',
            ),
          ),
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-a',
              name: 'first_tool',
              success: true,
              content: 'first done',
            ),
          ),
        ],
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(result, hasLength(2));
    expect(result[0].content, contains('second_tool'));
    expect(result[0].content, contains('second done'));
    expect(result[1].content, contains('first_tool'));
    expect(result[1].content, contains('first done'));
    expect(result.every((message) => message.isToolResultBubble), isTrue);
  });

  test('renders failed tool results as error view messages', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'call',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-failed',
              name: 'dangerous_tool',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
      AiMessage(
        id: 'failed-result',
        conversationId: 'conversation',
        role: AiMessageRole.tool,
        parts: const [
          AiContentPart.toolResult(
            toolResult: AiToolResult(
              toolCallId: 'call-failed',
              name: 'dangerous_tool',
              success: false,
              content: 'permission denied',
            ),
          ),
        ],
        createdAt: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.isError, isTrue);
    expect(result.single.content, contains('permission denied'));
  });

  test('keeps an unmatched tool call visible as a pending tool bubble', () {
    final result = mapper.mapHistory([
      AiMessage(
        id: 'pending-call',
        conversationId: 'conversation',
        role: AiMessageRole.assistant,
        parts: const [
          AiContentPart.toolCall(
            toolCall: AiToolCall(
              id: 'call-pending',
              name: 'long_running_tool',
              arguments: {},
            ),
          ),
        ],
        createdAt: _epoch,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.isToolResultBubble, isTrue);
    expect(result.single.content, contains('long_running_tool'));
  });

  test('maps the active stream snapshot to the current assistant item', () {
    final result = mapper.mapStreaming(
      messageId: 'streaming',
      snapshot: const AiStreamSnapshot(
        requestId: 'request',
        text: 'partial',
        reasoning: 'thinking',
        status: AiStreamStatus.streaming,
      ),
    );

    expect(result.id, 'streaming');
    expect(result.role, 'assistant');
    expect(result.content, contains('partial'));
    expect(result.content, contains('thinking'));
    expect(result.isError, isFalse);
  });
}

final _epoch = DateTime.utc(2026, 9, 10);
