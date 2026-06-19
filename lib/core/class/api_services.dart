// ignore_for_file: avoid_print
import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:fatoora/core/class/statusrequest.dart';
import 'package:fatoora/core/functions/checkinternet.dart';
import 'package:fatoora/linkapi.dart';

typedef JsonDecoder<R> = R Function(Map<String, dynamic> json);

class ApiService {
  final Dio _dio;
  final int maxRetries;
  final Duration retryDelay;
  String? accessToken; 
  String? refreshToken; 
  ApiService({
    BaseOptions? options,
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 500),
    this.accessToken,
    this.refreshToken,
  }) : _dio = Dio(options ??
            BaseOptions(
              
               baseUrl: AppLink.server,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              validateStatus: (status) => status != null && status >= 200 && status < 600,
            )) {
    _dio.interceptors.addAll([
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (accessToken != null && accessToken!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }

          _log('➡️ [REQUEST] ${options.method} ${options.uri}');
          _log('Headers: ${options.headers}');
          _log('Query: ${options.queryParameters}');
          _log('Data: ${options.data}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _log("✅ [RESPONSE] ${response.statusCode}: ${response.data}");
          return handler.next(response);
        },
        onError: (DioException e, handler) async {
          _log("❌ [ERROR] ${e.response?.statusCode} - ${e.message}");

          final status = e.response?.statusCode;
          if (status == 401 && refreshToken != null) {
            final refreshed = await _attemptTokenRefresh();
            if (refreshed == true) {
              try {
                final requestOptions = e.requestOptions;
                final opts = Options(
                  method: requestOptions.method,
                  headers: requestOptions.headers,
                );
                opts.headers?['Authorization'] = 'Bearer $accessToken';
                final clonedResp = await _dio.request(
                  requestOptions.path,
                  data: requestOptions.data,
                  queryParameters: requestOptions.queryParameters,
                  options: opts,
                );
                return handler.resolve(clonedResp);
              } catch (inner) {
             
                _log('Retry after refresh failed: $inner');
              }
            }
          }

          return handler.next(e);
        },
      ),
    ]);
  }


  void _log(String message) {

    print(message);
  }

  Future<bool> _attemptTokenRefresh() async {

    _log('Attempting token refresh (placeholder)...');
    await Future.delayed(const Duration(milliseconds: 300));

    return false; 
  }

  Map<String, dynamic>? _safeMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
   
    return null;
  }
  Left<StatusRequest, R> _mapDioExceptionToLeft<R>(DioException e) {
    final type = e.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout) {
      return const Left(StatusRequest.timeout);
    } else if (type == DioExceptionType.connectionError) {
      return const Left(StatusRequest.offlinefailure);
    } else if (type == DioExceptionType.badResponse) {
      final status = e.response?.statusCode ?? 0;
      if (status >= 500) return const Left(StatusRequest.serverfailure);
      if (status == 401) return const Left(StatusRequest.unauthorized);
      return const Left(StatusRequest.serverfailure);
    } else if (type == DioExceptionType.unknown) {
      return const Left(StatusRequest.failure);
    }
    return const Left(StatusRequest.failure);
  }

  Future<Either<StatusRequest, R>> get<R>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<R>? decoder, 
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    if (!await checkInternet()) return const Left(StatusRequest.offlinefailure);

    int attempt = 0;
    while (true) {
      try {
        final response = await _dio.get(
          url,
          queryParameters: queryParameters,
          options: Options(headers: headers),
          cancelToken: cancelToken,
        ).timeout(timeout ?? const Duration(seconds: 30));

        final code = response.statusCode ?? 0;
        if (code == 204) {

          if (decoder != null) {
        
            return Right(decoder(<String, dynamic>{}));
          }
          return Right(<String, dynamic>{} as R);
        }

        final map = _safeMap(response.data);
        if (map == null) {
      
          if (R == Map<String, dynamic>) {
            return Right(Map<String, dynamic>.from({'data': response.data}) as R);
          }
          return const Left(StatusRequest.failure);
        }

        if (decoder != null) {
          return Right(decoder(map));
        } else {
          return Right(map as R);
        }
      } on DioException catch (e) {
        final left = _mapDioExceptionToLeft<R>(e);
        if (_isRetryable(e) && attempt < maxRetries) {
          attempt++;
          final delay = retryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
          continue;
        }
        return left;
      } catch (e) {
        _log('Unexpected get error: $e');
        return const Left(StatusRequest.failure);
      }
    }
  }

  Future<Either<StatusRequest, R>> post<R>(
    String url,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
    JsonDecoder<R>? decoder,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    if (!await checkInternet()) return const Left(StatusRequest.offlinefailure);

    int attempt = 0;
    while (true) {
      try {
        final response = await _dio.post(
          url,
          data: data,
          options: Options(headers: headers),
          cancelToken: cancelToken,
        ).timeout(timeout ?? const Duration(seconds: 30));

        final code = response.statusCode ?? 0;
        if (code == 204) {
          if (decoder != null) return Right(decoder(<String, dynamic>{}));
          return Right(<String, dynamic>{} as R);
        }

        final map = _safeMap(response.data);
        if (map == null) {
          if (R == Map<String, dynamic>) {
            return Right(Map<String, dynamic>.from({'data': response.data}) as R);
          }
          return const Left(StatusRequest.failure);
        }

        if (decoder != null) return Right(decoder(map));
        return Right(map as R);
      } on DioException catch (e) {
        final left = _mapDioExceptionToLeft<R>(e);
        if (_isRetryable(e) && attempt < maxRetries) {
          attempt++;
          final delay = retryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
          continue;
        }
        return left;
      } catch (e) {
        _log('Unexpected post error: $e');
        return const Left(StatusRequest.failure);
      }
    }
  }

  Future<Either<StatusRequest, R>> put<R>(
    String url,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
    JsonDecoder<R>? decoder,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    if (!await checkInternet()) return const Left(StatusRequest.offlinefailure);

    try {
      final response = await _dio.put(
        url,
        data: data,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      ).timeout(timeout ?? const Duration(seconds: 30));

      final code = response.statusCode ?? 0;
      if (code == 204) {
        if (decoder != null) return Right(decoder(<String, dynamic>{}));
        return Right(<String, dynamic>{} as R);
      }

      final map = _safeMap(response.data);
      if (map == null) {
        if (R == Map<String, dynamic>) {
          return Right(Map<String, dynamic>.from({'data': response.data}) as R);
        }
        return const Left(StatusRequest.failure);
      }

      if (decoder != null) return Right(decoder(map));
      return Right(map as R);
    } on DioException catch (e) {
      return _mapDioExceptionToLeft<R>(e);
    } catch (e) {
      _log('Unexpected put error: $e');
      return const Left(StatusRequest.failure);
    }
  }

  Future<Either<StatusRequest, R>> delete<R>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<R>? decoder,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    if (!await checkInternet()) return const Left(StatusRequest.offlinefailure);

    try {
      final response = await _dio.delete(
        url,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      ).timeout(timeout ?? const Duration(seconds: 30));

      final code = response.statusCode ?? 0;
      if (code == 204) {
        if (decoder != null) return Right(decoder(<String, dynamic>{}));
        return Right(<String, dynamic>{} as R);
      }

      final map = _safeMap(response.data);
      if (map == null) {
        if (R == Map<String, dynamic>) {
          return Right(Map<String, dynamic>.from({'data': response.data}) as R);
        }
        return const Left(StatusRequest.failure);
      }

      if (decoder != null) return Right(decoder(map));
      return Right(map as R);
    } on DioException catch (e) {
      return _mapDioExceptionToLeft<R>(e);
    } catch (e) {
      _log('Unexpected delete error: $e');
      return const Left(StatusRequest.failure);
    }
  }

  bool _isRetryable(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) return true;
    final status = e.response?.statusCode ?? 0;
    if (status >= 500 && status < 600) return true;
    return false;
  }
}
