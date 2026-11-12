// Loopin — opciones de una línea con la explicación plegada detrás de «?»
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// El botón «?»: abre o cierra la explicación.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: open ? tr.hideHelp : tr.showHelp,
      isSelected: open,
      onPressed: onPressed,
      icon: const Icon(Icons.help_outline, size: 20),
      selectedIcon: const Icon(Icons.help, size: 20),
    );
  }
}

/// La explicación, que aparece debajo al tocar «?».
class HelpText extends StatelessWidget {
  const HelpText({super.key, required this.open, required this.text, this.padding});

  final bool open;
  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.topCenter,
      child: open
          ? Padding(
              padding: padding ?? const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(text, style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Una opción: título, una línea debajo, «?» con la explicación y, a la
/// derecha, lo que haga falta (un interruptor, un botón…). Tocar la fila hace
/// lo mismo que [onTap].
class OptionTile extends StatefulWidget {
  const OptionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.help,
    this.leading,
    this.trailing,
    this.onTap,
    this.toggled,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String title;
  final Widget? subtitle;
  final String? help;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Para lectores de pantalla: es un interruptor encendido o apagado.
  final bool? toggled;
  final EdgeInsetsGeometry padding;

  /// Con un interruptor a la derecha.
  factory OptionTile.toggle({
    Key? key,
    required String title,
    String? subtitle,
    String? help,
    Widget? leading,
    required bool value,
    required ValueChanged<bool>? onChanged,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16),
  }) => OptionTile(
    key: key,
    title: title,
    subtitle: subtitle == null ? null : Text(subtitle),
    help: help,
    leading: leading,
    toggled: value,
    onTap: onChanged == null ? null : () => onChanged(!value),
    trailing: ExcludeSemantics(
      child: Switch(value: value, onChanged: onChanged),
    ),
    padding: padding,
  );

  @override
  State<OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<OptionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = widget;
    final enabled = w.onTap != null || w.toggled == null;
    final row = Row(
      children: [
        if (w.leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: theme.colorScheme.onSurfaceVariant),
            child: w.leading!,
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: enabled ? null : theme.disabledColor,
                  ),
                ),
                if (w.subtitle != null)
                  DefaultTextStyle.merge(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: w.subtitle!,
                  ),
              ],
            ),
          ),
        ),
        if (w.help != null)
          HelpButton(open: _open, onPressed: () => setState(() => _open = !_open)),
        ?w.trailing,
      ],
    );
    return Padding(
      padding: w.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            toggled: w.toggled,
            button: w.onTap != null,
            child: InkWell(borderRadius: BorderRadius.circular(8), onTap: w.onTap, child: row),
          ),
          if (w.help != null) HelpText(open: _open, text: w.help!),
        ],
      ),
    );
  }
}

/// Título de una sección con, si hace falta, su «?».
class SectionTitle extends StatefulWidget {
  const SectionTitle(this.text, {super.key, this.help, this.style, this.padding = EdgeInsets.zero});

  final String text;
  final String? help;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;

  @override
  State<SectionTitle> createState() => _SectionTitleState();
}

class _SectionTitleState extends State<SectionTitle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Padding(
      padding: w.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(header: true, child: Text(w.text, style: w.style)),
                ),
                if (w.help != null)
                  HelpButton(open: _open, onPressed: () => setState(() => _open = !_open)),
              ],
            ),
          ),
          if (w.help != null) HelpText(open: _open, text: w.help!),
        ],
      ),
    );
  }
}

/// Una línea de texto pequeño con su «?» al lado.
class HelpLine extends StatefulWidget {
  const HelpLine(this.text, {super.key, required this.help});

  final String text;
  final String help;

  @override
  State<HelpLine> createState() => _HelpLineState();
}

class _HelpLineState extends State<HelpLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.text, style: small)),
            HelpButton(open: _open, onPressed: () => setState(() => _open = !_open)),
          ],
        ),
        HelpText(open: _open, text: widget.help),
      ],
    );
  }
}
