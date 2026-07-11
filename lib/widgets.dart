import 'package:flutter/material.dart';

import 'theme.dart';

/// Dashboard stat tile: muted label over a semibold value, with an optional
/// footnote and state dot.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.footnote,
    this.footnoteDotColor,
  });

  final String label;
  final String value;
  final String? footnote;
  final Color? footnoteDotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BmsColors.cardInner,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: BmsColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: BmsColors.textPrimary,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (footnoteDotColor != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: footnoteDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    footnote!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: BmsColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// App-bar leading mark: the bolt in the accent gradient.
class GradientBoltMark extends StatelessWidget {
  const GradientBoltMark({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => BmsColors.accent.createShader(bounds),
      child: Icon(Icons.bolt, color: Colors.white, size: size),
    );
  }
}
