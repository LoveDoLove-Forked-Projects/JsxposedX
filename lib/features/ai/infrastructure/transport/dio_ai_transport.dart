import 'dart:async';

import 'package:JsxposedX/features/ai/domain/models/ai_system_models.dart';
import 'package:JsxposedX/features/ai/domain/ports/ai_protocol_adapter.dart';
import 'package:dio/dio.dart';

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
    return AiTransportResponse(
      statusCode: response.statusCode ?? 0,
      headers: Map.unmodifiable(response.headers.map),
      body: responseBody.stream,
    );
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
