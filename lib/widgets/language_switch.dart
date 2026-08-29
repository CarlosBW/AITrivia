import 'package:flutter/material.dart';

import '../services/locale_controller.dart';
import '../theme/app_theme.dart';

class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<Locale>(
      valueListenable: LocaleController.instance.locale,
      builder: (context, locale, _) {
        final isEn = locale.languageCode == 'en';

        return Container(
          height: 38,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(context.radii.sm),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr(null),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LangOption(
                label: 'EN',
                selected: isEn,
                onTap: () => LocaleController.instance.setLocale('en'),
              ),
              _LangOption(
                label: 'ES',
                selected: !isEn,
                onTap: () => LocaleController.instance.setLocale('es'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LangOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        height: double.infinity,
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(context.radii.xs),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? colorScheme.onPrimary : colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
