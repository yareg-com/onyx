import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../globals.dart';
import '../managers/account_manager.dart';
import '../managers/settings_manager.dart';
import '../enums/liquid_glass_quality.dart';
import '../widgets/avatar_widget.dart';

class SearchDialogContent extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String username) onSelect;

  const SearchDialogContent({
    super.key,
    required this.controller,
    required this.onSelect,
  });

  @override
  State<SearchDialogContent> createState() => _SearchDialogContentState();
}

class _SearchDialogContentState extends State<SearchDialogContent>
    with TickerProviderStateMixin {
  final List<String> _results = [];
  Timer? _debounce;
  bool _loading = false;
  String _error = '';
  int _hoveredIndex = -1;
  String? _cachedToken;

  final FocusNode _focusNode = FocusNode();

  late AnimationController _focusAnimController;
  late Animation<double> _focusAnim;

  late AnimationController _hoverAnimController;
  late Animation<double> _hoverAnim;

  @override
  void initState() {
    super.initState();
    _focusAnimController = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _focusAnim = CurvedAnimation(parent: _focusAnimController, curve: Curves.easeOut);

    _hoverAnimController = AnimationController(
      duration: const Duration(milliseconds: 160),
      vsync: this,
    );
    _hoverAnim = CurvedAnimation(parent: _hoverAnimController, curve: Curves.easeOut);

    _loadToken();

    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (_focusNode.hasFocus) {
        _focusAnimController.forward();
      } else {
        _focusAnimController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _focusAnimController.dispose();
    _hoverAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final acc = await AccountManager.getCurrentAccount();
    if (acc != null) _cachedToken = await AccountManager.getToken(acc);
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
    if (mounted) setState(() {});
  }

  Future<void> _search(String q) async {
    final query = q.trim().replaceFirst('@', '');
    if (query.isEmpty) {
      if (mounted) setState(() { _results.clear(); _error = ''; _loading = false; });
      return;
    }
    if (mounted) setState(() { _loading = true; _error = ''; });
    try {
      if (_cachedToken == null) await _loadToken();
      final res = await http.get(
        Uri.parse('$serverBase/users?query=$query'),
        headers: _cachedToken != null ? {'authorization': 'Bearer $_cachedToken'} : {},
      );
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final data = jsonDecode(res.body);
      final List list = data is List ? data : (data['results'] as List? ?? []);
      if (mounted) setState(() { _results..clear()..addAll(list.map((e) => e['username'].toString())); });
    } catch (e) {
      if (mounted) setState(() => _error = 'Search error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SettingsManager.liquidGlassOnSearch,
        SettingsManager.liquidGlassSearchQuality,
        SettingsManager.liquidGlassSearchBlur,
        SettingsManager.liquidGlassSearchTint,
        SettingsManager.liquidGlassSearchSaturation,
        SettingsManager.liquidGlassSearchChromatic,
        SettingsManager.liquidGlassSearchRefractive,
        SettingsManager.liquidGlassSearchLightIntensity,
        SettingsManager.liquidGlassSearchThickness,
      ]),
      builder: (context, _) {
        final useGlass = SettingsManager.liquidGlassOnSearch.value;
        final content = _buildContent(context, useGlass);
        return _wrapSurface(context, content);
      },
    );
  }

  // ── Standard surface wrapper — no card, Spotlight-style ─────────────────────

  Widget _wrapSurface(BuildContext context, Widget content) => content;

  // ── Content (shared between both modes) ─────────────────────────────────────

  Widget _buildContent(BuildContext context, bool useGlass) {
    final hasQuery = widget.controller.text.trim().isNotEmpty;
    if (useGlass) return _buildGlassContent(context, hasQuery);
    return _buildStandardContent(context, hasQuery);
  }

  // Standard: pill floats alone, results in separate frosted card below
  Widget _buildStandardContent(BuildContext context, bool hasQuery) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 700;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchFieldStandard(context),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: hasQuery
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: isDesktop
                        ? _BackdropBlurWrapper(
                            sigma: 14,
                            child: _standardResultsCard(context, cs, isDesktop),
                          )
                        : _standardResultsCard(context, cs, isDesktop),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _standardResultsCard(BuildContext context, ColorScheme cs, bool isDesktop) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: isDesktop ? 0.88 : 1.0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _loading ? 2 : 0,
            child: _loading
                ? LinearProgressIndicator(
                    borderRadius: BorderRadius.circular(2),
                    color: cs.primary.withValues(alpha: 0.8),
                    backgroundColor: Colors.transparent,
                  )
                : const SizedBox.shrink(),
          ),
          _resultsList(context, false),
        ],
      ),
    );
  }

  // Glass: pill floats alone, results in separate GlassCard below
  Widget _buildGlassContent(BuildContext context, bool hasQuery) {
    final quality    = SettingsManager.liquidGlassSearchQuality.value;
    final blur           = SettingsManager.liquidGlassSearchBlur.value;
    final tint           = SettingsManager.liquidGlassSearchTint.value;
    final saturation     = SettingsManager.liquidGlassSearchSaturation.value;
    final chromatic      = SettingsManager.liquidGlassSearchChromatic.value;
    final refractive     = SettingsManager.liquidGlassSearchRefractive.value;
    final lightIntensity = SettingsManager.liquidGlassSearchLightIntensity.value;
    final thickness      = SettingsManager.liquidGlassSearchThickness.value;

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Floating glass pill for the search field
        GlassCard(
          useOwnLayer: true,
          settings: settings,
          quality: glassQuality,
          padding: EdgeInsets.zero,
          shape: LiquidRoundedRectangle(borderRadius: 50),
          clipBehavior: Clip.antiAlias,
          child: _searchFieldGlass(context),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: hasQuery
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GlassCard(
                    useOwnLayer: true,
                    settings: settings,
                    quality: glassQuality,
                    padding: EdgeInsets.zero,
                    shape: LiquidRoundedRectangle(borderRadius: 18),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: _loading ? 2 : 0,
                          child: _loading
                              ? LinearProgressIndicator(
                                  borderRadius: BorderRadius.circular(2),
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                  backgroundColor: Colors.transparent,
                                )
                              : const SizedBox.shrink(),
                        ),
                        _resultsList(context, true),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Standard search field ────────────────────────────────────────────────────

  Widget _searchFieldStandard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: SettingsManager.elementBrightness,
      builder: (context, brightness, _) {
        final baseColor = SettingsManager.getElementColor(
          colorScheme.surfaceContainerHighest,
          brightness,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: AnimatedBuilder(
            animation: Listenable.merge([_focusAnim, _hoverAnim]),
            builder: (context, _) {
              final focusT = _focusAnim.value;
              final hoverT = _hoverAnim.value;
              final borderColor = Color.lerp(
                Color.lerp(colorScheme.outline.withValues(alpha: 0.18), colorScheme.primary.withValues(alpha: 0.50), hoverT)!,
                colorScheme.primary,
                focusT,
              )!;
              final iconColor = Color.lerp(
                Color.lerp(colorScheme.onSurface.withValues(alpha: 0.45), colorScheme.primary.withValues(alpha: 0.75), hoverT)!,
                colorScheme.primary,
                focusT,
              )!;
              final bgColor = Color.lerp(
                baseColor,
                Color.lerp(baseColor, colorScheme.primary, 0.05)!,
                hoverT * (1.0 - focusT),
              )!;
              final shadowAlpha = hoverT * 0.06 + focusT * 0.12;
              final shadowBlur = 16.0 + focusT * 10.0;
              return MouseRegion(
                cursor: SystemMouseCursors.text,
                onEnter: (_) => _hoverAnimController.forward(),
                onExit: (_) => _hoverAnimController.reverse(),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: borderColor, width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 6)),
                      BoxShadow(color: colorScheme.primary.withValues(alpha: shadowAlpha), blurRadius: shadowBlur),
                    ],
                  ),
                  child: _searchTextField(context, colorScheme.onSurface, iconColor, colorScheme.onSurface.withValues(alpha: 0.4), colorScheme.primary),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Spotlight-style glass search field ───────────────────────────────────────

  Widget _searchFieldGlass(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black.withValues(alpha: 0.85);
    final hintColor = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.35);
    final iconColor = isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.5);
    final cursorColor = isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.8);
    final pillColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.07);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: Container(
          decoration: BoxDecoration(
            color: pillColor,
            borderRadius: BorderRadius.circular(50),
          ),
          child: _searchTextField(context, textColor, iconColor, hintColor, cursorColor,
            fontSize: 16,
            iconSize: 24,
            verticalPadding: 14,
          ),
        ),
      ),
    );
  }

  Widget _searchTextField(
    BuildContext context,
    Color textColor,
    Color iconColor,
    Color hintColor,
    Color cursorColor, {
    double fontSize = 15,
    double iconSize = 22,
    double verticalPadding = 13,
  }) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: true,
      onChanged: _onChanged,
      style: TextStyle(color: textColor, fontSize: fontSize),
      cursorColor: cursorColor,
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(Icons.search_rounded, color: iconColor, size: iconSize),
        ),
        hintText: 'Search @username...',
        hintStyle: TextStyle(color: hintColor, fontSize: fontSize),
        suffixIcon: widget.controller.text.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.close_rounded, color: textColor.withValues(alpha: 0.5), size: 18),
                onPressed: () { widget.controller.clear(); _onChanged(''); },
              )
            : null,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      ),
    );
  }

  // ── Results list ─────────────────────────────────────────────────────────────

  Widget _resultsList(BuildContext context, bool useGlass) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) return const SizedBox.shrink();

    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: colorScheme.error.withValues(alpha: 0.75)),
            const SizedBox(width: 8),
            Text('Search error', style: TextStyle(color: colorScheme.error.withValues(alpha: 0.75), fontSize: 14)),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      final textColor = useGlass
          ? (isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.3))
          : colorScheme.onSurface.withValues(alpha: 0.45);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 34, color: textColor),
            const SizedBox(height: 10),
            Text('No users found', style: TextStyle(color: textColor, fontSize: 14)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _results.length,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          itemBuilder: (_, i) {
            final username = _results[i];
            final isHovered = _hoveredIndex == i;

            Color hoverColor;
            Color usernameColor;
            Color nameColor;
            if (useGlass) {
              hoverColor = isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08);
              usernameColor = isDark ? Colors.white : Colors.black.withValues(alpha: 0.85);
              nameColor = isDark
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.45);
            } else {
              hoverColor = colorScheme.primary.withValues(alpha: 0.09);
              usernameColor = colorScheme.onSurface;
              nameColor = colorScheme.primary;
            }

            return MouseRegion(
              onEnter: (_) => setState(() => _hoveredIndex = i),
              onExit: (_) => setState(() => _hoveredIndex = -1),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onSelect(username),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isHovered ? hoverColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      AvatarWidget(
                        key: ValueKey('avatar-$username'),
                        username: username,
                        tokenProvider: avatarTokenProvider,
                        avatarBaseUrl: serverBase,
                        size: 40,
                        editable: false,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '@',
                                style: TextStyle(color: nameColor, fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              TextSpan(
                                text: username,
                                style: TextStyle(color: usernameColor, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: isHovered ? 1.0 : 0.0,
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: useGlass
                              ? (isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.35))
                              : colorScheme.primary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BackdropBlurWrapper extends StatelessWidget {
  const _BackdropBlurWrapper({required this.child, this.sigma = 22});
  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
