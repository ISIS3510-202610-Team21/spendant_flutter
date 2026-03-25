import 'package:flutter_test/flutter_test.dart';
import 'package:spendant/src/services/receipt_scan_service.dart';

void main() {
  group('ReceiptScanService.extractFormattedAmount', () {
    test('prefers the dollar-marked amount over a larger identifier', () {
      final formattedAmount =
          ReceiptScanService.extractFormattedAmount(const <String>[
            'FACTURA ELECTRONICA No. 220320260001',
            r'TOTAL A PAGAR 220320260001 $ 25.500',
          ]);

      expect(formattedAmount, '25,500');
    });

    test('inherits total context from the previous line', () {
      final formattedAmount = ReceiptScanService.extractFormattedAmount(
        const <String>[
          'NIT 900123456',
          'TOTAL',
          r'Referencia 8456721901  $18.900',
        ],
      );

      expect(formattedAmount, '18,900');
    });

    test(
      'still extracts the best total when no currency symbol is present',
      () {
        final formattedAmount = ReceiptScanService.extractFormattedAmount(
          const <String>['NIT 900123456', 'SUBTOTAL 18.000', 'TOTAL 21.420'],
        );

        expect(formattedAmount, '21,420');
      },
    );
  });
}
