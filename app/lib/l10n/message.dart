// Loopin — textos con parámetros y plurales (un subconjunto de ICU MessageFormat)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Lo que entiende (lo mismo que comprueba Weblate con «ICU MessageFormat»):
//   «Pista {n}»                                     parámetro
//   «{n, plural, one {# capa} other {# capas}}»     plural (# = el número; también =0, =1…)
//   «{x, select, on {encendida} other {apagada}}»   según un valor
// Los apóstrofos son texto normal (no sirven para escapar llaves): en francés e
// italiano se puede escribir «l'app» o «l’app». No se pueden escribir llaves sueltas.

/// Categoría de plural de [n] en [lang] (reglas de CLDR para números enteros).
String pluralCategory(String lang, num n) {
  final i = n.abs().truncate();
  final whole = n == n.truncate();
  switch (lang) {
    case 'fr':
    case 'pt':
      // 0 y 1 van en singular («0 mesure», «1 compasso» / «0 compasso»)
      return i == 0 || i == 1 ? 'one' : 'other';
    default:
      return whole && i == 1 ? 'one' : 'other';
  }
}

/// Un texto ya analizado, listo para rellenar.
class Message {
  Message._(this._parts);

  /// Analiza [source]. Lanza [FormatException] si está mal escrito.
  factory Message.parse(String source) {
    final p = _Parser(source);
    final parts = p.message(inPlural: false);
    if (!p.done) throw FormatException('Llave «}» de más', source, p.pos);
    return Message._(parts);
  }

  final List<_Part> _parts;

  /// Los nombres de los parámetros que usa (para comprobar las traducciones).
  Set<String> get argNames {
    final out = <String>{};
    void walk(List<_Part> parts) {
      for (final part in parts) {
        if (part is _Arg) out.add(part.name);
        if (part is _Choice) {
          out.add(part.name);
          part.options.values.forEach(walk);
        }
      }
    }

    walk(_parts);
    return out;
  }

  /// Las opciones de cada plural o select (para comprobar las traducciones).
  Map<String, Set<String>> get choices {
    final out = <String, Set<String>>{};
    void walk(List<_Part> parts) {
      for (final part in parts) {
        if (part is _Choice) {
          out
              .putIfAbsent('${part.name}:${part.plural ? 'plural' : 'select'}', () => {})
              .addAll(part.options.keys);
          part.options.values.forEach(walk);
        }
      }
    }

    walk(_parts);
    return out;
  }

  /// Rellena el texto. [number] da formato a los números de «#».
  String format(Map<String, Object?> args, {required String lang, String Function(num)? number}) {
    final out = StringBuffer();
    void write(List<_Part> parts, num? hash) {
      for (final part in parts) {
        switch (part) {
          case _Text(:final text):
            out.write(text);
          case _Hash():
            final n = hash ?? 0;
            out.write(number != null ? number(n) : '$n');
          case _Arg(:final name):
            out.write(args[name] ?? '{$name}');
          case _Choice(:final name, :final plural, :final options):
            final value = args[name];
            if (plural) {
              final n = value is num ? value : num.tryParse('$value') ?? 0;
              final chosen =
                  options['=$n'] ??
                  options['=${n.truncate()}'] ??
                  options[pluralCategory(lang, n)] ??
                  options['other']!;
              write(chosen, n);
            } else {
              write(options['$value'] ?? options['other']!, hash);
            }
        }
      }
    }

    write(_parts, null);
    return out.toString();
  }
}

sealed class _Part {}

class _Text extends _Part {
  _Text(this.text);
  final String text;
}

class _Hash extends _Part {}

class _Arg extends _Part {
  _Arg(this.name);
  final String name;
}

class _Choice extends _Part {
  _Choice(this.name, this.plural, this.options);
  final String name;
  final bool plural;
  final Map<String, List<_Part>> options;
}

class _Parser {
  _Parser(this.src);

  final String src;
  int pos = 0;

  bool get done => pos >= src.length;

  Never _fail(String why) => throw FormatException(why, src, pos);

  /// Texto hasta una «}» que cierra (sin consumirla) o hasta el final.
  List<_Part> message({required bool inPlural}) {
    final parts = <_Part>[];
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        parts.add(_Text(text.toString()));
        text.clear();
      }
    }

    while (!done) {
      final c = src[pos];
      if (c == '}') break;
      if (c == '{') {
        flush();
        parts.add(_argument());
      } else if (c == '#' && inPlural) {
        flush();
        parts.add(_Hash());
        pos++;
      } else {
        text.write(c);
        pos++;
      }
    }
    flush();
    return parts;
  }

  void _spaces() {
    while (!done && src[pos].trim().isEmpty) {
      pos++;
    }
  }

  String _word() {
    _spaces();
    final start = pos;
    while (!done && !',{}'.contains(src[pos]) && src[pos].trim().isNotEmpty) {
      pos++;
    }
    final w = src.substring(start, pos);
    _spaces();
    return w;
  }

  _Part _argument() {
    pos++; // «{»
    final name = _word();
    if (name.isEmpty || !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      _fail('Nombre de parámetro no válido: «$name»');
    }
    if (done) _fail('Falta «}»');
    if (src[pos] == '}') {
      pos++;
      return _Arg(name);
    }
    if (src[pos] != ',') _fail('Se esperaba «,» o «}»');
    pos++;
    final type = _word();
    if (type != 'plural' && type != 'select') _fail('Tipo no admitido: «$type»');
    if (done || src[pos] != ',') _fail('Se esperaba «,» después de «$type»');
    pos++;
    final plural = type == 'plural';
    final options = <String, List<_Part>>{};
    while (true) {
      _spaces();
      if (done) _fail('Falta «}»');
      if (src[pos] == '}') {
        pos++;
        break;
      }
      final key = _word();
      if (key.isEmpty) _fail('Falta el nombre de una opción');
      if (plural && !RegExp(r'^(=\d+|zero|one|two|few|many|other)$').hasMatch(key)) {
        _fail('Opción de plural no válida: «$key»');
      }
      if (done || src[pos] != '{') _fail('Se esperaba «{» después de «$key»');
      pos++;
      if (options.containsKey(key)) _fail('Opción repetida: «$key»');
      options[key] = message(inPlural: plural);
      if (done || src[pos] != '}') _fail('Falta «}» al final de «$key»');
      pos++;
    }
    if (!options.containsKey('other')) _fail('Falta la opción «other»');
    return _Choice(name, plural, options);
  }
}
