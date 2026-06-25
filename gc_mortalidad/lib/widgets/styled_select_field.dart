import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';

class StyledSelectField extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;
  final String? errorText;
  final bool enabled;
  final bool flat;
  final bool compact;

  const StyledSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.icon,
    required this.onTap,
    this.errorText,
    this.enabled = true,
    this.flat = false,
    this.compact = false,
  });

  InputDecoration _decoration(BuildContext context) {
    final hasError = errorText != null && errorText!.trim().isNotEmpty;
    final base = flat
        ? AppInputStyles.decorationFlat(
            context,
            labelText: label,
            prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            fillColor: enabled
                ? null
                : (context.isDarkTheme
                    ? AppColors.darkSurface
                    : Colors.grey.shade50),
          )
        : AppInputStyles.decoration(
            context,
            labelText: label,
            prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            fillColor: enabled
                ? null
                : (context.isDarkTheme
                    ? AppColors.darkSurface
                    : Colors.grey.shade50),
            accentBorder: !hasError,
            isDense: compact,
            contentPadding: compact
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
                : null,
          );

    if (!hasError) return base;

    final errorBorder = AppInputStyles.borderOf(context, color: AppColors.error);
    final errorFocused = AppInputStyles.borderOf(
      context,
      color: AppColors.error,
      focused: true,
    );

    return base.copyWith(
      enabledBorder: errorBorder,
      focusedBorder: errorFocused,
      errorBorder: errorBorder,
      focusedErrorBorder: errorFocused,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null && value!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppInputStyles.radius),
          child: InputDecorator(
            decoration: _decoration(context).copyWith(
              suffixIcon: compact
                  ? null
                  : Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
            child: Text(
              hasValue ? value! : placeholder,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 14 : 15,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                color: hasValue
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        AppFieldError(errorText),
      ],
    );
  }
}
