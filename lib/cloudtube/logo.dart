import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Логотип CLOUDTUBE в шапке: значок-телевизор + слово, как на сайте.
class CtLogo extends StatelessWidget {
  final double height;

  const CtLogo({super.key, this.height = 24});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset('assets/icon.svg', height: height + 4),
        const SizedBox(width: 4),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'CLOUD', style: TextStyle(color: colors.onSurface)),
            const TextSpan(text: 'TUBE', style: TextStyle(color: CtColors.logoRed)),
          ]),
          style: TextStyle(
              fontSize: height * 0.8, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1),
        ),
      ],
    );
  }
}
