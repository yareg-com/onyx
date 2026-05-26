// lib/widgets/adaptive_nav_bar.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../enums/liquid_glass_quality.dart';
import '../managers/settings_manager.dart';
import '../widgets/animated_nav_icon.dart';

class AdaptiveNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool isDesktop;
  final double navWidth;
  final double leftPad;
  final Color navBackground;

  const AdaptiveNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.isDesktop,
    required this.navWidth,
    required this.leftPad,
    required this.navBackground,
  });

  static const _tabs = [
    (Icons.chat_bubble,       NavIconAnimationType.bounce, 300),
    (Icons.group,             NavIconAnimationType.bounce, 400),
    (Icons.bookmark_outlined, NavIconAnimationType.bounce, 500),
    (Icons.person,            NavIconAnimationType.bounce, 600),
    (Icons.settings,          NavIconAnimationType.spin,   700),
  ];

  int get _safeIndex => selectedIndex < 5 ? selectedIndex : 4;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.liquidGlassOnNavBar,
      builder: (context, onNavBar, _) {
        if (isDesktop || !onNavBar) return _buildStandard(context);
        return _buildLiquid(context);
      },
    );
  }

  // ── Standard ──────────────────────────────────────────────────────────────────

  Widget _buildStandard(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 18.0,
          left: leftPad,
          right: isDesktop ? 0 : 70,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 58,
            width: isDesktop ? navWidth : navWidth + 20,
            decoration: BoxDecoration(
              color: navBackground,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 10),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: isDesktop
                      ? null
                      : (details) {
                          final tabWidth = navWidth / 5;
                          final newIndex =
                              (details.localPosition.dx / tabWidth)
                                  .floor()
                                  .clamp(0, 4);
                          if (newIndex != _safeIndex) {
                            HapticFeedback.selectionClick();
                            onTap(newIndex);
                          }
                        },
                  child: SizedBox(
                    width: navWidth,
                    height: 58,
                    child: _buildNavigationBar(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationBar(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return NavigationBar(
      selectedIndex: _safeIndex,
      onDestinationSelected: onTap,
      height: 58,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      backgroundColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: 0.15),
      destinations: List.generate(_tabs.length, (i) {
        final (icon, anim, delay) = _tabs[i];
        return NavigationDestination(
          icon: AnimatedNavIcon(
            icon: icon,
            size: 22,
            isSelected: _safeIndex == i,
            animationType: anim,
            entryDelay: delay,
          ),
          selectedIcon: AnimatedNavIcon(
            icon: icon,
            size: 24,
            color: primary,
            isSelected: _safeIndex == i,
            animationType: anim,
            entryDelay: delay,
          ),
          label: '',
        );
      }),
    );
  }

  // ── Liquid Glass ──────────────────────────────────────────────────────────────

  Widget _buildLiquid(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SettingsManager.liquidGlassNavBarQuality,
        SettingsManager.liquidGlassExpansion,
        SettingsManager.liquidGlassBlur,
        SettingsManager.liquidGlassTint,
        SettingsManager.liquidGlassSaturation,
        SettingsManager.liquidGlassChromatic,
        SettingsManager.liquidGlassRefractive,
        SettingsManager.liquidGlassLightIntensity,
        SettingsManager.liquidGlassThickness,
      ]),
      builder: (context, _) {
        final quality         = SettingsManager.liquidGlassNavBarQuality.value;
        final expansion       = SettingsManager.liquidGlassExpansion.value;
        final blur            = SettingsManager.liquidGlassBlur.value;
        final tint            = SettingsManager.liquidGlassTint.value;
        final saturation      = SettingsManager.liquidGlassSaturation.value;
        final chromatic       = SettingsManager.liquidGlassChromatic.value;
        final refractive      = SettingsManager.liquidGlassRefractive.value;
        final lightIntensity  = SettingsManager.liquidGlassLightIntensity.value;
        final thickness       = SettingsManager.liquidGlassThickness.value;

        final rawQuality = switch (quality) {
          LiquidGlassQuality.fast    => GlassQuality.standard,
          LiquidGlassQuality.medium  => GlassQuality.minimal,
          LiquidGlassQuality.quality => GlassQuality.premium,
        };
        final glassQuality = (isDesktop && rawQuality == GlassQuality.premium)
            ? GlassQuality.standard
            : rawQuality;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final tintColor = isDark
            ? Colors.white.withValues(alpha: tint)
            : Colors.black.withValues(alpha: tint);

        final glassSettings = LiquidGlassSettings(
          thickness: thickness,
          blur: blur,
          chromaticAberration: chromatic,
          lightIntensity: lightIntensity,
          refractiveIndex: refractive,
          saturation: saturation,
          ambientStrength: 1,
          lightAngle: 0.75 * math.pi,
          glassColor: tintColor,
        );

        return SafeArea(
          bottom: true,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: 18.0,
              left: leftPad,
              right: isDesktop ? 0 : 70,
            ),
            child: SizedBox(
              width: isDesktop ? navWidth : navWidth + 20,
              child: GlassBottomBar(
                tabs: List.generate(
                  _tabs.length,
                  (i) => GlassBottomBarTab(icon: Icon(_tabs[i].$1)),
                ),
                selectedIndex: _safeIndex,
                onTabSelected: onTap,
                horizontalPadding: 10,
                verticalPadding: 0,
                barHeight: 58,
                quality: glassQuality,
                indicatorExpansion: expansion,
                glassSettings: glassSettings,
                selectedIconColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}
