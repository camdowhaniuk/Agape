import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AppLogoVariant { brand, mark, square }

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 64,
    this.color,
    this.variant = AppLogoVariant.brand,
    this.semanticLabel = 'Agape',
  });

  final double size;
  final Color? color;
  final AppLogoVariant variant;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget rendered = switch (variant) {
      AppLogoVariant.brand => Image.asset(
          'assets/agape_logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          color: color,
          colorBlendMode: color != null ? BlendMode.srcIn : null,
        ),
      AppLogoVariant.mark => SvgPicture.asset(
          'assets/logo/agape_logo_mark.svg',
          width: size,
          height: size,
          fit: BoxFit.contain,
          colorFilter: color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null,
        ),
      AppLogoVariant.square => SvgPicture.asset(
          'assets/logo/agape_icon_square.svg',
          width: size,
          height: size,
          fit: BoxFit.contain,
          colorFilter: color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null,
        ),
    };

    return Semantics(
      label: semanticLabel,
      child: rendered,
    );
  }
}
