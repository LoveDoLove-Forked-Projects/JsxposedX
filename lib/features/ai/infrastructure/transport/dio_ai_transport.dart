import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DioAiTransport implements AiTransport {
  const DioAiTransport(this._dio);

  final Dio _dio;

  @override
  Future<AiTransportResponse> send(
    PreparedAiRequest request, {
    required AiCancellationToken cancellation,
  }) async {
    final cancelToken = CancelToken();
    if (cancellation.isCancelled) {
      cancelToken.cancel('AI request cancelled before sending');
    } else {
      unawaited(
        cancellation.cancelled.then((_) {
          if (!cancelToken.isCancelled) {
            cancelToken.cancel('AI request cancelled');
          }
        }),
      );
    }

    late final Response<ResponseBody> response;
    try {
      response = await _dio.postUri<ResponseBody>(
        request.uri,
        data: request.body,
        cancelToken: cancelToken,
        options: Options(
          headers: request.headers,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      throw AiTransportException(_mapFailure(error));
    }
    final responseBody = response.data;
    if (responseBody == null) {
      throw StateError('AI transport returned an empty response body');
    }
    if (kDebugMode) {
      developer.log(
        '[AI][HTTP] ${request.uri} status=${response.statusCode} '
        'content-type=${response.headers.value('content-type') ?? 'unknown'}',
        name: 'AiTransport',
      );
    }
    return AiTransportResponse(
      statusCode: response.statusCode ?? 0,
      headers: Map.unmodifiable(response.headers.map),
      body: _debugBody(responseBody.stream),
    );
  }

  Stream<List<int>> _debugBody(Stream<List<int>> source) async* {
    await for (final chunk in source) {
      if (kDebugMode) {
        final text = utf8.decode(chunk, allowMalformed: true);
        final preview = text.length <= 4000
            ? text
            : '${text.substring(0, 4000)}...[truncated]';
        developer.log(
          '[AI][SSE] bytes=${chunk.length}\n$preview',
          name: 'AiTransport',
        );
      }
      yield chunk;
    }
  }

  static AiFailure _mapFailure(DioException error) {
    final code = switch (error.type) {
      DioExceptionType.cancel => AiFailureCode.cancelled,
      DioExceptionType.connectionTimeout => AiFailureCode.connectTimeout,
      DioExceptionType.receiveTimeout => AiFailureCode.receiveTimeout,
      DioExceptionType.connectionError ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.badCertificate => AiFailureCode.networkUnavailable,
      DioExceptionType.badResponse ||
      DioExceptionType.unknown => AiFailureCode.unknown,
    };
    return AiFailure(
      code: code,
      messageKey: 'ai.error.${code.name}',
      retryable:
          code == AiFailureCode.networkUnavailable ||
          code == AiFailureCode.connectTimeout ||
          code == AiFailureCode.receiveTimeout,
    );
  }
}
