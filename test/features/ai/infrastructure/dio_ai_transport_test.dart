import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:JsxposedX/features/ai/application/chat/ai_cancellation_controller.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:JsxposedX/features/ai/infrastructure/transport/dio_ai_transport.dart';

void main() {
  test('keeps response body as a byte stream', () async {
    final responseController = StreamController<Uint8List>();
    final dio = Dio()
      ..httpClientAdapter = _StreamingAdapter(responseController.stream);
    final transport = DioAiTransport(dio);

    final response = await transport.send(
      PreparedAiRequest(
        uri: Uri.parse('https://example.test/v1/chat/completions'),
        headers: const {'Accept': 'text/event-stream'},
        body: const {'stream': true},
      ),
      cancellation: AiCancellationController(),
    );
    final received = <String>[];
    final subscription = response.body.listen((bytes) {
      received.add(utf8.decode(bytes));
    });

    responseController.add(Uint8List.fromList(utf8.encode('first')));
    await Future<void>.delayed(Duration.zero);
    expect(received, ['first']);

    responseController.add(Uint8List.fromList(utf8.encode('second')));
    await responseController.close();
    await subscription.asFuture<void>();
    expect(received, ['first', 'second']);
  });
}

class _StreamingAdapter implements HttpClientAdapter {
  _StreamingAdapter(this.stream);

  final Stream<Uint8List> stream;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
