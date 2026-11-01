import 'dart:convert';

import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('getMyRecords coincide aunque el código difiera en mayúsculas', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyUserCode: 'jlsf',
      AppStrings.recordsTable: [
        jsonEncode({
          'id': 'a',
          'reporte': 'ingreso',
          'fecha': '2026-10-09',
          'usuario': 'JLSF',
          'synced': false,
        }),
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    expect(storage.getMyRecords(), hasLength(1));
  });
}
