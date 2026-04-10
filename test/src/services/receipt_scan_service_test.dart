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

    test('selects the Colombian receipt total over tax and payment values', () {
      final analysis = ReceiptScanService.analyzeAmounts(const <String>[
        '2pc @ \$24,900/pc',
        '49,800',
        '2pc @ \$2,900/pc',
        '5,800',
        'Total \$ 55,600 T. Credito -55,600',
        'Base IVA 46,723',
        'IVA Total 8,877',
      ]);

      expect(analysis.formattedSelectedAmount, '55,600');
      expect(analysis.confidence, 'alto');
      expect(
        analysis.selected?.reasons,
        containsAll(<String>[
          'linea con total',
          'frase de total fuerte',
          'magnitud compatible',
        ]),
      );

      final taxCandidate = analysis.candidates.firstWhere(
        (candidate) => candidate.normalizedValue == 8877,
      );
      final paymentCandidate = analysis.candidates.firstWhere(
        (candidate) =>
            candidate.rawText.contains('-') &&
            candidate.lineText.contains('Credito'),
      );
      final unitCandidate = analysis.candidates.firstWhere(
        (candidate) => candidate.normalizedValue == 24900,
      );

      expect(taxCandidate.reasons, contains('contexto iva/impuesto'));
      expect(paymentCandidate.reasons, contains('contexto de pago'));
      expect(unitCandidate.reasons, contains('precio unitario'));
    });

    test('handles noisy OCR total keywords such as T0TAL', () {
      final analysis = ReceiptScanService.analyzeAmounts(const <String>[
        'SUBTOTAL 46.723',
        'IVA 8.877',
        'T0TAL COP 55.600',
      ]);

      expect(analysis.formattedSelectedAmount, '55,600');
      expect(analysis.selected?.isSelected, isTrue);
      expect(analysis.confidence, anyOf('alto', 'medio'));
    });

    test(
      'ignores total counters such as TOTAL CAJAS and picks monetary total',
      () {
        final analysis = ReceiptScanService.analyzeAmounts(const <String>[
          'TOTAL ITEMS: 1',
          'TOTAL CAJAS: 1',
          'Subtotal \$17,563',
          'IVA 19 \$3,337',
          'Total \$20,900',
          'Por cobrar \$20,900',
        ]);

        expect(analysis.formattedSelectedAmount, '20,900');

        final countCandidate = analysis.candidates.firstWhere(
          (candidate) =>
              candidate.normalizedValue == 1 &&
              candidate.lineText.contains('TOTAL CAJAS'),
        );
        expect(countCandidate.reasons, contains('conteo de items/cajas'));
      },
    );

    test('normalizes OCR digits such as O in the total amount', () {
      final analysis = ReceiptScanService.analyzeAmounts(const <String>[
        'TOTAL: \$ 1,95O',
        'I.V.A. 19% \$ 1,639',
        'IVA \$ 311',
        'RECIBIDO: \$ 2,000',
        'CAMBIO: \$ 50',
        'I.V.A. 5% \$ 0',
      ]);

      expect(analysis.formattedSelectedAmount, '1,950');
      expect(
        analysis.candidates.any((candidate) => candidate.normalizedValue == 0),
        isTrue,
      );
    });

    test(
      'ignores bare transaction identifiers when money candidates exist',
      () {
        final analysis = ReceiptScanService.analyzeAmounts(const <String>[
          'ID N°: Angelica Garci Trans: 170320',
          'Fecha: 01/04/26 15:15 Tienda N°: 66100',
          '2pc @ \$24,900/pc 49,800',
          '2pc @ \$2,900/pc 5,800',
          'Total \$',
          '55,600',
          'T. Credito',
          '-55,600',
          'IVA Total 8,877',
        ]);

        expect(analysis.formattedSelectedAmount, '55,600');

        final transCandidate = analysis.candidates.firstWhere(
          (candidate) => candidate.normalizedValue == 170320,
        );
        expect(
          transCandidate.reasons,
          containsAll(<String>[
            'parece identificador',
            'entero largo sin formato monetario',
          ]),
        );
      },
    );
  });
}
