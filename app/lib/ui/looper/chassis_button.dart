// Loopin — botón con el aspecto del chasis
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../theme.dart';

/// Botón con el aspecto del chasis: borde fino y etiqueta en mayúsculas.
class ChassisButton extends StatelessWidget {
  const ChassisButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.onPressed,
    this.label,
    this.tooltip,
    this.selected = false,
    this.isToggle = false,
    this.dense = false,
  });

  final LoopinPalette palette;
  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  /// Es un interruptor (encendido o apagado), no una acción.
  final bool isToggle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final enabled = onPressed != null;
    final fg = !enabled ? p.dim.withValues(alpha: 0.45) : (selected ? p.chassis : p.ink);
    final button = Material(
      color: selected ? p.ink : p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? p.ink : p.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          constraints: BoxConstraints(minHeight: dense ? 40 : 48, minWidth: 48),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.label(size: 14, color: fg),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: isToggle ? selected : null,
      label: tooltip,
      child: tooltip != null ? Tooltip(message: tooltip, child: button) : button,
    );
  }
}
