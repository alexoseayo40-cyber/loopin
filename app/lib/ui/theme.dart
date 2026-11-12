// Loopin — colores y tipografías: la app es la cara de un pedal
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

/// Color del chasis del pedal. Cada uno tiene versión clara y oscura.
enum Chassis {
  classic('Clásico'),
  red('Rojo'),
  green('Verde'),
  blue('Azul');

  const Chassis(this.label);
  final String label;
}

/// Tema (claro, oscuro o el del sistema) y color del chasis.
@immutable
class Appearance {
  const Appearance({this.mode = ThemeMode.system, this.chassis = Chassis.classic});

  final ThemeMode mode;
  final Chassis chassis;

  Appearance copyWith({ThemeMode? mode, Chassis? chassis}) =>
      Appearance(mode: mode ?? this.mode, chassis: chassis ?? this.chassis);

  @override
  bool operator ==(Object other) =>
      other is Appearance && other.mode == mode && other.chassis == chassis;

  @override
  int get hashCode => Object.hash(mode, chassis);
}

/// Tipografías incluidas en la app (licencia OFL, ver assets/fonts).
abstract final class LoopinFonts {
  /// Etiquetas, como la serigrafía de un pedal.
  static const label = 'BarlowCondensed';

  /// Números de la pantalla.
  static const display = 'ShareTechMono';
}

/// Colores de la pantalla del looper.
///
/// Los LEDs y la pantalla de tempo van siempre sobre negro (el surco del
/// anillo, el hueco de la pantalla), como en un pedal de verdad. Por eso los
/// colores de estado son los mismos con cualquier chasis y en claro u oscuro.
@immutable
class LoopinPalette extends ThemeExtension<LoopinPalette> {
  const LoopinPalette({
    required this.chassis,
    required this.panel,
    required this.edge,
    required this.ink,
    required this.dim,
  });

  /// Fondo: el metal pintado del pedal.
  final Color chassis;

  /// Zonas un poco hundidas (la fila de la pista elegida).
  final Color panel;

  /// Bordes y separadores.
  final Color edge;

  /// Texto e iconos sobre el chasis.
  final Color ink;

  /// Texto secundario sobre el chasis.
  final Color dim;

  // --- Iguales con cualquier chasis ---

  /// Surco de los anillos de luz.
  static const groove = Color(0xFF101012);

  /// LED apagado dentro del surco.
  static const ledOff = Color(0xFF34343A);

  /// Hueco de la pantalla de tempo y sus números.
  static const well = Color(0xFF0B0B0C);
  static const display = Color(0xFFFFB347);
  static const displayDim = Color(0xFF8A6A3A);

  /// Tapa metálica del pulsador.
  static const metal = Color(0xFFC4C2B9);
  static const metalPressed = Color(0xFFA9A79E);
  static const metalEdge = Color(0xFF85837B);
  static const metalInk = Color(0xFF2B2A27);

  /// Colores de estado: graba, suena, overdub, cuenta de entrada y parado.
  static const rec = Color(0xFFFF4B3E);
  static const play = Color(0xFF3DDC97);
  static const dub = Color(0xFFFFB020);
  static const count = Color(0xFFFFFFFF);
  static const stopped = Color(0xFF7C8794);

  static LoopinPalette of(BuildContext context) =>
      Theme.of(context).extension<LoopinPalette>() ?? forChassis(Chassis.classic, Brightness.dark);

  static LoopinPalette forChassis(Chassis chassis, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (chassis) {
      Chassis.classic =>
        dark
            ? const LoopinPalette(
                chassis: Color(0xFF1B1B1D),
                panel: Color(0xFF252528),
                edge: Color(0xFF36363B),
                ink: Color(0xFFECEAE3),
                dim: Color(0xFF9D9B92),
              )
            : const LoopinPalette(
                chassis: Color(0xFFE8E1CE),
                panel: Color(0xFFDCD4BE),
                edge: Color(0xFFC6BDA4),
                ink: Color(0xFF26231D),
                dim: Color(0xFF6A6454),
              ),
      Chassis.red =>
        dark
            ? const LoopinPalette(
                chassis: Color(0xFF3A1716),
                panel: Color(0xFF47201E),
                edge: Color(0xFF5E2B28),
                ink: Color(0xFFF6E7E2),
                dim: Color(0xFFCB9F98),
              )
            : const LoopinPalette(
                chassis: Color(0xFFC53D2D),
                panel: Color(0xFFB43425),
                edge: Color(0xFF9C2B1E),
                ink: Color(0xFFFFF4EA),
                dim: Color(0xFFF7CFC6),
              ),
      Chassis.green =>
        dark
            ? const LoopinPalette(
                chassis: Color(0xFF17322B),
                panel: Color(0xFF1F3E36),
                edge: Color(0xFF2B5045),
                ink: Color(0xFFE4F2EB),
                dim: Color(0xFF93B6A8),
              )
            : const LoopinPalette(
                chassis: Color(0xFFBFDCCB),
                panel: Color(0xFFAFD0BD),
                edge: Color(0xFF94BDA6),
                ink: Color(0xFF17322A),
                dim: Color(0xFF486A5C),
              ),
      Chassis.blue =>
        dark
            ? const LoopinPalette(
                chassis: Color(0xFF15243A),
                panel: Color(0xFF1C2F4A),
                edge: Color(0xFF29405F),
                ink: Color(0xFFE3ECF7),
                dim: Color(0xFF93A9C5),
              )
            : const LoopinPalette(
                chassis: Color(0xFFBCD2E8),
                panel: Color(0xFFABC5DE),
                edge: Color(0xFF90AECB),
                ink: Color(0xFF14273D),
                dim: Color(0xFF465E79),
              ),
    };
  }

  /// Etiqueta en mayúsculas, como la serigrafía de un pedal.
  TextStyle label({double size = 13, Color? color, double spacing = 1.2}) => TextStyle(
    fontFamily: LoopinFonts.label,
    fontWeight: FontWeight.w600,
    fontSize: size,
    letterSpacing: spacing,
    height: 1.1,
    color: color ?? ink,
  );

  @override
  LoopinPalette copyWith({Color? chassis, Color? panel, Color? edge, Color? ink, Color? dim}) =>
      LoopinPalette(
        chassis: chassis ?? this.chassis,
        panel: panel ?? this.panel,
        edge: edge ?? this.edge,
        ink: ink ?? this.ink,
        dim: dim ?? this.dim,
      );

  @override
  LoopinPalette lerp(LoopinPalette? other, double t) {
    if (other == null) return this;
    return LoopinPalette(
      chassis: Color.lerp(chassis, other.chassis, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
    );
  }
}

/// Tema de Material para toda la app (ajustes incluidos) con la paleta del
/// pedal dentro.
ThemeData buildLoopinTheme(Chassis chassis, Brightness brightness) {
  final palette = LoopinPalette.forChassis(chassis, brightness);
  final seed = switch (chassis) {
    Chassis.classic => const Color(0xFFB86E00),
    Chassis.red => const Color(0xFFC53D2D),
    Chassis.green => const Color(0xFF2E7D5B),
    Chassis.blue => const Color(0xFF2F5F9E),
  };
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    extensions: [palette],
    sliderTheme: const SliderThemeData(trackHeight: 3),
  );
}
