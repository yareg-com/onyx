import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../enums/liquid_glass_quality.dart';
import '../managers/settings_manager.dart';

class AdaptiveGlassCard extends StatelessWidget {
  const AdaptiveGlassCard({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 8),
    this.onTap,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  // Liquid glass только на Android и iOS; на десктопе (Windows/Linux/macOS) — стандартный рендер.
  static bool get _glassAllowed =>
      !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!_glassAllowed) return _buildStandard(context);
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.liquidGlassOnCards,
      builder: (_, onCards, __) {
        if (!onCards) return _buildStandard(context);
        return _buildGlass(context);
      },
    );
  }

  Widget _buildGlass(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SettingsManager.liquidGlassCardsQuality,
        SettingsManager.liquidGlassCardsBlur,
        SettingsManager.liquidGlassCardsTint,
        SettingsManager.liquidGlassCardsSaturation,
        SettingsManager.liquidGlassCardsChromatic,
        SettingsManager.liquidGlassCardsRefractive,
        SettingsManager.liquidGlassCardsLightIntensity,
        SettingsManager.liquidGlassCardsThickness,
      ]),
      builder: (context, _) {
        final quality        = SettingsManager.liquidGlassCardsQuality.value;
        final blur           = SettingsManager.liquidGlassCardsBlur.value;
        final tint           = SettingsManager.liquidGlassCardsTint.value;
        final saturation     = SettingsManager.liquidGlassCardsSaturation.value;
        final chromatic      = SettingsManager.liquidGlassCardsChromatic.value;
        final refractive     = SettingsManager.liquidGlassCardsRefractive.value;
        final lightIntensity = SettingsManager.liquidGlassCardsLightIntensity.value;
        final thickness      = SettingsManager.liquidGlassCardsThickness.value;

        final glassQuality = switch (quality) {
          LiquidGlassQuality.fast    => GlassQuality.standard,
          LiquidGlassQuality.medium  => GlassQuality.minimal,
          LiquidGlassQuality.quality => GlassQuality.premium,
        };

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final tintColor = isDark
            ? Colors.white.withValues(alpha: tint)
            : Colors.black.withValues(alpha: tint);

        final settings = LiquidGlassSettings(
          thickness: thickness,
          blur: blur,
          chromaticAberration: chromatic,
          lightIntensity: lightIntensity,
          refractiveIndex: refractive,
          saturation: saturation,
          ambientStrength: 0.8,
          lightAngle: 0.75 * math.pi,
          glassColor: tintColor,
        );

        final shape = LiquidRoundedRectangle(borderRadius: borderRadius);

        final card = GlassCard(
          useOwnLayer: true,
          settings: settings,
          quality: glassQuality,
          padding: padding,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: child,
        );

        if (onTap != null) {
          return GestureDetector(onTap: onTap, child: card);
        }
        return card;
      },
    );
  }

  Widget _buildStandard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: SettingsManager.elementOpacity,
      builder: (_, opacity, __) {
        return ValueListenableBuilder<double>(
          valueListenable: SettingsManager.elementBrightness,
          builder: (_, brightness, __) {
            final baseColor = SettingsManager.getElementColor(
              cs.surfaceContainerHighest,
              brightness,
            );
            final border = Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.15),
              width: 1,
            );
            if (onTap != null) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: Material(
                  color: baseColor.withValues(alpha: opacity),
                  child: InkWell(
                    onTap: onTap,
                    child: Container(
                      padding: padding,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        border: border,
                      ),
                      child: child,
                    ),
                  ),
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: border,
                ),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}
