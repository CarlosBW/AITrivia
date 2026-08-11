import 'package:flutter/material.dart';

import '../features/shop/coin_shop_screen.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';

/// Eye-catching entry point into the coin shop — purple gradient (matching
/// the app's other hero CTAs) with an amber coin accent, reused on Home and
/// Profile so the shop has one consistent visual identity.
class BuyCoinsButton extends StatelessWidget {
  const BuyCoinsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CoinShopScreen()),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6C4FF2), Color(0xFF8A6BFF)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.monetization_on_outlined,
                  color: context.appColors.reward,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).buyCoinsButtonLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.add_circle_outline,
                color: context.appColors.reward,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
