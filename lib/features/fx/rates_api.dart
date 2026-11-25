import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

abstract class RatesApi {
  Future<Map<String, Decimal>> latestPerUsd();
}

class ErApiRatesApi implements RatesApi {
  ErApiRatesApi([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;

  @override
  Future<Map<String, Decimal>> latestPerUsd() async {
    final response = await _dio.get<Object?>(
      'https://open.er-api.com/v6/latest/USD',
    );
    final body = response.data;
    if (body is! Map || body['result'] != 'success') {
      throw const FormatException('Exchange rate request was unsuccessful');
    }
    final rates = body['rates'];
    if (rates is! Map<String, dynamic>) {
      throw const FormatException('Expected a rates object');
    }
    final parsed = <String, Decimal>{};
    for (final entry in rates.entries) {
      final value = entry.value;
      if (value is! num || !value.isFinite) continue;
      final rate = Decimal.parse(value.toString());
      if (rate > Decimal.zero) parsed[entry.key] = rate;
    }
    return parsed;
  }
}
