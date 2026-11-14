// Loopin — antes de los tests: los textos de los 6 idiomas, con el español puesto
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:loopin/l10n/language.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // ignore: invalid_use_of_visible_for_testing_member
  AppLanguage.loadForTests();
  await testMain();
}
