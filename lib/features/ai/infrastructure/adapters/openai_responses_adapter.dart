import 'dart:convert';

import 'package:JsxposedX/features/ai/domain/events/ai_stream_event.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/openai_chat_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/adapters/protocol_adapter_support.dart';
import 'package:JsxposedX/features/ai/infrastructure/transport/sse_decoder.dart';

class OpenAiResponsesAdapter implements AiProtocolAdapter {
  const OpenAiResponsesAdapter({this.maxSseEventBytes = 1024 * 1024});

  final int maxSseEventBytes;

  @override
  String get id => 'openai.responses.v1';

  @override
  PreparedAiRequest prepare(
    AiRequest request, {
    required AiAdapterContext context,
  }) {
    final headers = <String, String>{
      'Accept': 'text/event-stream',
      'Content-Type': 'application/json',
      ...request.connection.customHeaders,
    };
    var endpoint = resolveAiEndpoint(
      request.connection,
      AiEndpointKind.responses,
      'responses',
    );
    endpoint = applyAiAuthentication(
      endpoint: endpoint,
      headers: headers,
      context: context,
    );
    final body = <String, Object?>{
      'model': request.model.id,
      'input': request.messages.expand(_inputItems).toList(growable: false),
      'stream': request.options.stream,
    };
    final options = request.options;
    if (options.maxOutputTokens != null) {
      body['max_output_tokens'] = options.maxOutputTokens;
    }
    if (options.temperature != null) body['temperature'] = options.temperature;
    if (options.topP != null) body['top_p'] = options.topP;
    if (options.reasoningEffort != null) {
      body['reasoning'] = {'effort': options.reasoningEffort};
    }
    if (request.tools.isNotEmpty) {
      body['tools'] = request.tools
          .map(
            (tool) => <String, Object?>{
              'type': 'function',
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.inputSchema,
            },
          )
          .toList(growable: false);
    }
    return PreparedAiRequest(uri: endpoint, headers: headers, body: body);
  }

  @override
  Stream<AiStreamEvent> decodeStream(
    Stream<List<int>> bytes, {
    required String requestId,
  }) async* {
    var sequence = 0;
    var terminal = false;
    yield AiStreamEvent.started(requestId: requestId, sequence: sequence++);
    try {
      await for (final event in AiSseDecoder(
        maxEventBytes: maxSseEventBytes,
      ).decode(bytes)) {
        if (event.data == '[DONE]') continue;
        final raw = jsonDecode(event.data);
        if (raw is! Map) {
          throw const FormatException('Responses event is not an object');
        }
        final map = Map<String, Object?>.from(raw);
        if (aiPayloadIsError(map)) {
          yield AiStreamEvent.failed(
            requestId: requestId,
            sequence: sequence++,
            failure: aiProviderPayloadFailure(map),
          );
          return;
        }
        final type = map['type']?.toString() ?? event.event;
        switch (type) {
          case 'response.output_text.delta':
            final delta = map['delta']?.toString() ?? '';
            if (delta.isNotEmpty) {
              yield AiStreamEvent.textDelta(
                requestId: requestId,
                sequence: sequence++,
                itemId: map['item_id']?.toString() ?? requestId,
                delta: delta,
              );
            }
          case 'response.reasoning_summary_text.delta' ||
              'response.reasoning_text.delta':
            final delta = map['delta']?.toString() ?? '';
            if (delta.isNotEmpty) {
              yield AiStreamEvent.reasoningDelta(
                requestId: requestId,
                sequence: sequence++,
                itemId: map['item_id']?.toString() ?? requestId,
                delta: delta,
              );
            }
          case 'response.output_item.added':
            final item = map['item'];
            if (item is Map && item['type'] == 'function_call') {
              yield AiStreamEvent.toolCallDelta(
                requestId: requestId,
                sequence: sequence++,
                index: aiIntValue(map['output_index']) ?? 0,
                toolCallId: item['call_id']?.toString(),
                name: item['name']?.toString(),
              );
            }
          case 'response.function_call_arguments.delta':
            yield AiStreamEvent.toolCallDelta(
              requestId: requestId,
              sequence: sequence++,
              index: aiIntValue(map['output_index']) ?? 0,
              toolCallId: map['item_id']?.toString(),
              argumentsDelta: map['delta']?.toString(),
            );
          case 'response.completed':
            final response = map['response'];
            final responseMap = response is Map
                ? Map<String, Object?>.from(response)
                : const <String, Object?>{};
            final usage = _usage(responseMap['usage']);
            if (usage != null) {
              yield AiStreamEvent.usage(
                requestId: requestId,
                sequence: sequence++,
                value: usage,
              );
            }
            terminal = true;
            yield AiStreamEvent.completed(
              requestId: requestId,
              sequence: sequence++,
              reason: _finishReason(responseMap),
            );
          case 'response.failed' || 'error':
            terminal = true;
            yield AiStreamEvent.failed(
              requestId: requestId,
              sequence: sequence++,
              failure: aiProviderPayloadFailure(map),
            );
        }
      }
      if (!terminal) {
        yield AiStreamEvent.failed(
          requestId: requestId,
          sequence: sequence++,
          failure: const AiFailure(
            code: AiFailureCode.protocolTruncated,
            messageKey: 'ai.error.protocolTruncated',
          ),
        );
      }
    } on FormatException {
      yield AiStreamEvent.failed(
        requestId: requestId,
        sequence: sequence++,
        failure: const AiFailure(
          code: AiFailureCode.protocolMalformed,
          messageKey: 'ai.error.protocolMalformed',
        ),
      );
    }
  }

  @override
  Stream<AiStreamEvent> decodeResponse(
    List<int> bytes, {
    required String requestId,
  }) async* {
    var sequence = 0;
    yield AiStreamEvent.started(requestId: requestId, sequence: sequence++);
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) throw const FormatException('Invalid response');
      final map = Map<String, Object?>.from(raw);
      if (aiPayloadIsError(map)) {
        yield AiStreamEvent.failed(
          requestId: requestId,
          sequence: sequence++,
          failure: aiProviderPayloadFailure(map),
        );
        return;
      }
      // A number of OpenAI-compatible gateways advertise Responses in their
      // model list but return a Chat Completions JSON envelope. Accept that
      // envelope without pretending it was an SSE stream.
      if (map['choices'] is List) {
        var skippedStarted = false;
        await for (final event in const OpenAiChatAdapter().decodeResponse(
          bytes,
          requestId: requestId,
        )) {
          if (event is AiResponseStarted && !skippedStarted) {
            skippedStarted = true;
            continue;
          }
          yield event;
        }
        return;
      }
      final output = map['output'];
      if (output is List) {
        for (var index = 0; index < output.length; index++) {
          final rawItem = output[index];
          if (rawItem is! Map) continue;
          final item = Map<String, Object?>.from(rawItem);
          if (item['type'] == 'function_call') {
            yield AiStreamEvent.toolCallDelta(
              requestId: requestId,
              sequence: sequence++,
              index: index,
              toolCallId: item['call_id']?.toString(),
              name: item['name']?.toString(),
              argumentsDelta: item['arguments']?.toString(),
            );
            continue;
          }
          final content = item['content'];
          if (content is! List) continue;
          for (final rawPart in content) {
            if (rawPart is! Map) continue;
            final part = Map<String, Object?>.from(rawPart);
            final text = part['text']?.toString() ?? '';
            if (text.isEmpty) continue;
            if (part['type'] == 'reasoning_text' ||
                part['type'] == 'summary_text') {
              yield AiStreamEvent.reasoningDelta(
                requestId: requestId,
                sequence: sequence++,
                itemId: item['id']?.toString() ?? requestId,
                delta: text,
              );
            } else if (part['type'] == 'output_text') {
              yield AiStreamEvent.textDelta(
                requestId: requestId,
                sequence: sequence++,
                itemId: item['id']?.toString() ?? requestId,
                delta: text,
              );
            }
          }
        }
      }
      final usage = _usage(map['usage']);
      if (usage != null) {
        yield AiStreamEvent.usage(
          requestId: requestId,
          sequence: sequence++,
          value: usage,
        );
      }
      yield AiStreamEvent.completed(
        requestId: requestId,
        sequence: sequence++,
        reason: _finishReason(map),
      );
    } on FormatException {
      yield AiStreamEvent.failed(
        requestId: requestId,
        sequence: sequence++,
        failure: const AiFailure(
          code: AiFailureCode.protocolMalformed,
          messageKey: 'ai.error.protocolMalformed',
        ),
      );
    }
  }

  static Iterable<Map<String, Object?>> _inputItems(AiMessage message) sync* {
    final text = aiTextContent(message);
    if (text.isNotEmpty) {
      final role = switch (message.role) {
        AiMessageRole.system => 'developer',
        AiMessageRole.tool => 'user',
        AiMessageRole.user => 'user',
        AiMessageRole.assistant => 'assistant',
      };
      final contentType = role == 'assistant' ? 'output_text' : 'input_text';
      yield {
        'role': role,
        'content': [
          {'type': contentType, 'text': text},
        ],
      };
    }
    for (final part in message.parts.whereType<AiToolCallPart>()) {
      yield {
        'type': 'function_call',
        'call_id': part.toolCall.id,
        'name': part.toolCall.name,
        'arguments': jsonEncode(part.toolCall.arguments),
      };
    }
    for (final part in message.parts.whereType<AiToolResultPart>()) {
      yield {
        'type': 'function_call_output',
        'call_id': part.toolResult.toolCallId,
        'output': part.toolResult.content,
      };
    }
  }

  static AiUsage? _usage(Object? raw) {
    if (raw is! Map) return null;
    final input = aiIntValue(raw['input_tokens']);
    final output = aiIntValue(raw['output_tokens']);
    final total = aiIntValue(raw['total_tokens']);
    if (input == null && output == null && total == null) return null;
    return AiUsage(
      inputTokens: input ?? 0,
      outputTokens: output ?? 0,
      totalTokens: total ?? ((input ?? 0) + (output ?? 0)),
    );
  }

  static AiFinishReason _finishReason(Map<String, Object?> response) {
    return response['status']?.toString() == 'incomplete'
        ? AiFinishReason.length
        : AiFinishReason.stop;
  }
}
