import 'package:flutter/material.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';

class M3LoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;

  const M3LoadingIndicator({
    super.key,
    this.size = 64.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ExpressiveLoadingIndicator(
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
