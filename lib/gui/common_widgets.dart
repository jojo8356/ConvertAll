// common_widgets.dart, shared building blocks of the user interface.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/theme_model.dart';

/// Uppercase label that titles a section, a panel or a field.
class SectionLabel extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const SectionLabel(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final style = AppTheme.overline.copyWith(color: textColor);
    if (icon == null) {
      return Text(
        text.toUpperCase(),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13.0, color: textColor),
        const SizedBox(width: 5.0),
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Rounded square that holds an icon; marks a panel or a header.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.58, color: color),
    );
  }
}

/// Bordered surface that groups related content (a "panel" in the DA).
class PanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final bool clip;

  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.gapL),
    this.accent,
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accentColor = accent;
    // The accent is drawn as an overlay so the panel keeps hugging its
    // content (a stretched Row would make it as tall as the window).
    final body = accentColor == null
        ? Padding(padding: padding, child: child)
        : Stack(
            children: <Widget>[
              Padding(padding: padding, child: child),
              Positioned(
                left: 0.0,
                top: 0.0,
                bottom: 0.0,
                width: 3.0,
                child: ColoredBox(color: accentColor),
              ),
            ],
          );
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(AppTheme.panelRadius),
        border: Border.all(color: colors.hairline),
      ),
      clipBehavior: (clip || accentColor != null) ? Clip.antiAlias : Clip.none,
      child: body,
    );
  }
}

/// Text editor with an uppercase label placed above the field.
class LabelledTextEditor extends StatelessWidget {
  final String labelText;
  final String? errorText;
  final String? helperText;
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final bool showLabel;
  final TextStyle? style;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const LabelledTextEditor({
    super.key,
    required this.labelText,
    this.errorText,
    this.helperText,
    this.hintText,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.showLabel = true,
    this.style,
    this.suffixIcon,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0, left: 2.0),
            child: SectionLabel(
              labelText,
              color: enabled ? null : scheme.outline,
            ),
          ),
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          enabled: enabled,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          // Avoid losing focus when clicking on the unit table or elsewhere.
          onTapOutside: (event) {},
          style: (style ?? theme.textTheme.bodyLarge)?.copyWith(
            color: enabled ? scheme.onSurface : scheme.outline,
          ),
          decoration: InputDecoration(
            errorText: errorText,
            helperText: helperText,
            hintText: hintText,
            suffixIcon: suffixIcon,
            suffixIconColor: scheme.onSurfaceVariant,
            fillColor: enabled ? colors.sunken : colors.sunkenStrong,
          ),
        ),
      ],
    );
  }
}

/// Large editor used for the conversion values.
class ValueField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const ValueField({
    super.key,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      // Avoid losing focus when clicking on the unit table or elsewhere.
      onTapOutside: (event) {},
      style: AppTheme.valueText.copyWith(
        color: enabled ? scheme.onSurface : scheme.outline,
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14.0,
          vertical: 12.0,
        ),
        hintText: enabled ? '1' : null,
        hintStyle: AppTheme.valueText.copyWith(
          color: scheme.outline.withValues(alpha: 0.6),
        ),
        fillColor: enabled ? colors.sunken : colors.sunkenStrong,
      ),
    );
  }
}

/// Feedback bar shown under the conversion values.
class InfoBar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String? detail;

  const InfoBar({
    super.key,
    required this.icon,
    required this.color,
    required this.message,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final detailText = detail;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gapM,
        vertical: 9.0,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17.0, color: color),
          const SizedBox(width: AppTheme.gapS),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (detailText != null && detailText.isNotEmpty) ...<Widget>[
            const SizedBox(width: AppTheme.gapM),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 3.0,
                ),
                decoration: BoxDecoration(
                  color: colors.sunkenStrong,
                  borderRadius: BorderRadius.circular(7.0),
                ),
                child: Text(
                  detailText,
                  style: AppTheme.codeText.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rounded key cap followed by the action it triggers.
class KeyHint extends StatelessWidget {
  final String keyLabel;
  final String action;

  const KeyHint({super.key, required this.keyLabel, required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(5.0),
            border: Border.all(color: colors.hairline),
          ),
          child: Text(
            keyLabel,
            style: AppTheme.codeText.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 5.0),
        Text(action, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Colored dot telling whether an entry is empty, valid or invalid.
class ValidityDot extends StatelessWidget {
  final bool isValid;
  final bool hasContent;

  const ValidityDot({super.key, required this.isValid, required this.hasContent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final Color color;
    final String label;
    if (!hasContent) {
      color = theme.colorScheme.outline;
      label = 'empty';
    } else if (isValid) {
      color = colors.success;
      label = 'valid';
    } else {
      color = colors.danger;
      label = 'invalid';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8.0,
          height: 8.0,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6.0),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: 11.0,
          ),
        ),
      ],
    );
  }
}

/// Icon button that copies [text] and briefly confirms with a check mark.
class CopyIconButton extends StatefulWidget {
  final String text;
  final String tooltip;

  const CopyIconButton({
    super.key,
    required this.text,
    this.tooltip = 'Copy',
  });

  @override
  State<CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<CopyIconButton> {
  Timer? _resetTimer;
  var _copied = false;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() {
      _copied = true;
    });
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isEmpty = widget.text.trim().isEmpty;
    return IconButton(
      iconSize: 18.0,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30.0, minHeight: 30.0),
      tooltip: _copied ? 'Copied!' : widget.tooltip,
      onPressed: isEmpty ? null : _copy,
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        color: _copied
            ? colors.success
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Centered message used when a list, table or search has nothing to show.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final bool busy;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (busy)
              const SizedBox(
                width: 22.0,
                height: 22.0,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else
              Icon(icon, size: 26.0, color: scheme.outline),
            const SizedBox(height: AppTheme.gapM),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppTheme.gapXs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
