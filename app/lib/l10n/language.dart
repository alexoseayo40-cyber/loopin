// Loopin — el idioma de la app: el del móvil o el elegido en Ajustes
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io' show Directory, File;
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/prefs.dart';
import 'strings.dart';

/// El primero de [locales] (los idiomas del móvil, por orden de preferencia)
/// que tiene la app; si no tiene ninguno, inglés.
String languageFor(List<Locale> locales) {
  for (final l in locales) {
    if (kLanguages.contains(l.languageCode)) return l.languageCode;
  }
  return 'en';
}

/// Los textos para «Copiar resultados»: los de la app si está en español; si
/// no, los ingleses (ver `report_strings.dart`).
Strings get reportStrings => tr.lang == 'es' ? tr : (AppLanguage._loaded['en'] ?? tr);

/// Carga los textos y cambia de idioma.
abstract final class AppLanguage {
  /// Lo elegido en Ajustes: «» = el del móvil; si no, «es», «en»…
  static String get setting => _setting;
  static String _setting = '';

  /// El idioma que se está usando. Avisa al cambiar (la app se redibuja).
  static final ValueNotifier<String> current = ValueNotifier('es');

  /// El idioma del móvil, si lo tiene la app (si no, inglés).
  static String get system => languageFor(_systemLocales());

  /// Los idiomas del móvil (se cambia en los tests).
  @visibleForTesting
  static List<Locale> Function() systemLocales = () => PlatformDispatcher.instance.locales;
  static List<Locale> _systemLocales() => systemLocales();

  static final _loaded = <String, Strings>{};
  static Prefs _prefs = const Prefs();

  /// Al abrir la app: lee lo elegido y carga sus textos.
  static Future<void> init({Prefs prefs = const Prefs()}) async {
    _prefs = prefs;
    final saved = await prefs.get(Prefs.language);
    _setting = saved != null && kLanguages.contains(saved) ? saved : '';
    await _apply();
  }

  /// Elige el idioma («» = el del móvil) y lo guarda.
  static Future<void> choose(String code) async {
    _setting = kLanguages.contains(code) ? code : '';
    _prefs.set(Prefs.language, _setting);
    await _apply();
  }

  /// Han cambiado los idiomas del móvil.
  static Future<void> systemChanged() async {
    if (_setting.isEmpty) await _apply();
  }

  static Future<void> _apply() async {
    final lang = _setting.isEmpty ? system : _setting;
    final strings = await _load(lang);
    if (lang != 'es') await _load('en'); // para el informe
    useStrings(strings);
    current.value = lang;
  }

  /// Los textos de [lang] (y los de referencia, en español, para lo que falte).
  static Future<Strings> _load(String lang) async {
    final have = _loaded[lang];
    if (have != null) return have;
    final es = _loaded['es'] ??= Strings.fromJson('es', await _read('es'));
    if (lang == 'es') return es;
    return _loaded[lang] = Strings.fromJson(lang, await _read(lang), fallback: es);
  }

  static Future<String> _read(String lang) => rootBundle.loadString('assets/l10n/$lang.json');

  // ---------------------------------------------------------------- tests

  /// Carga los 6 idiomas desde la carpeta `assets/l10n` (los tests corren
  /// desde `app/`) y deja puesto [lang].
  @visibleForTesting
  static void loadForTests({String lang = 'es'}) {
    if (_loaded.length < kLanguages.length) {
      final dir = Directory('assets/l10n');
      String read(String l) => File('${dir.path}/$l.json').readAsStringSync();
      final es = _loaded['es'] = Strings.fromJson('es', read('es'));
      for (final l in kLanguages.skip(1)) {
        _loaded[l] = Strings.fromJson(l, read(l), fallback: es);
      }
    }
    useForTests(lang);
  }

  /// Cambia de idioma al momento (con todo ya cargado por [loadForTests]).
  @visibleForTesting
  static void useForTests(String lang, {String setting = ''}) {
    _setting = setting;
    useStrings(_loaded[lang]!);
    current.value = lang;
  }

  /// Los textos ya cargados de [lang] (para los tests).
  @visibleForTesting
  static Strings? loaded(String lang) => _loaded[lang];
}
