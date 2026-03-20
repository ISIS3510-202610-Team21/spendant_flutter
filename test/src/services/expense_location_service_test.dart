import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:spendant/src/services/expense_location_service.dart';

void main() {
  group('ExpenseLocationService', () {
    test('buildPlacemarkLabel removes repeated segments', () {
      const placemark = Placemark(
        name: 'Exito',
        street: 'Exito',
        locality: 'Bogota',
        administrativeArea: 'Bogota',
      );

      expect(
        ExpenseLocationService.buildPlacemarkLabel(placemark),
        'Exito, Bogota',
      );
    });

    test(
      'resolveLabel falls back to coordinates when geocoding fails',
      () async {
        final service = ExpenseLocationService(
          placemarkLookup: (_, _) async => throw Exception('offline'),
        );

        final label = await service.resolveLabel(
          latitude: 4.60971,
          longitude: -74.08175,
        );

        expect(label, '4.6097, -74.0817');
      },
    );

    test(
      'search preserves the typed place name while storing coordinates',
      () async {
        final service = ExpenseLocationService(
          addressLookup: (_) async => <Location>[
            Location(
              latitude: 4.6483,
              longitude: -74.2479,
              timestamp: DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
            ),
          ],
        );

        final result = await service.search('Exito Chapinero');

        expect(result, isNotNull);
        expect(result!.label, 'Exito Chapinero');
        expect(result.latitude, 4.6483);
        expect(result.longitude, -74.2479);
      },
    );

    test('looksLikeCoordinateLabel detects map-style coordinate labels', () {
      expect(
        ExpenseLocationService.looksLikeCoordinateLabel('4.6097, -74.0818'),
        isTrue,
      );
      expect(
        ExpenseLocationService.looksLikeCoordinateLabel('Exito Chapinero'),
        isFalse,
      );
    });
  });
}
