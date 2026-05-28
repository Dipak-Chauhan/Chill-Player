import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

enum M3EButtonVariant { filled, filledTonal, outlined, text, elevated }
enum M3EHapticLevel { none, light, medium, heavy }

class NeighborNotifier extends ChangeNotifier {
  bool isPressed = false;
  void setPressed(bool pressed) {
    if (isPressed != pressed) {
      isPressed = pressed;
      notifyListeners();
    }
  }
}

class SpringButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleDown;
  final BorderRadius? restBorderRadius;
  final BorderRadius? pressedBorderRadius;
  final NeighborNotifier? neighborNotifier;
  final M3EHapticLevel hapticLevel;
  final M3EButtonVariant? variant;
  final EdgeInsetsGeometry? padding;

  const SpringButton({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleDown = 0.94,
    this.restBorderRadius,
    this.pressedBorderRadius,
    this.neighborNotifier,
    this.hapticLevel = M3EHapticLevel.light,
    this.variant,
    this.padding,
  });

  @override
  State<SpringButton> createState() => _SpringButtonState();
}

class _SpringButtonState extends State<SpringButton> with TickerProviderStateMixin {
  late AnimationController _controller;
  late SpringSimulation _springSimulation;
  bool _isPressed = false;
  bool _neighborPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, lowerBound: 0.0, upperBound: 2.0);
    _controller.value = 1.0;

    widget.neighborNotifier?.addListener(_onNeighborChanged);
  }
  
  void _onNeighborChanged() {
    if (!mounted) return;
    setState(() {
      _neighborPressed = widget.neighborNotifier?.isPressed ?? false;
    });
  }

  @override
  void dispose() {
    widget.neighborNotifier?.removeListener(_onNeighborChanged);
    _controller.dispose();
    super.dispose();
  }

  void _triggerHaptic() {
    switch (widget.hapticLevel) {
      case M3EHapticLevel.light:
        HapticFeedback.lightImpact();
        break;
      case M3EHapticLevel.medium:
        HapticFeedback.mediumImpact();
        break;
      case M3EHapticLevel.heavy:
        HapticFeedback.heavyImpact();
        break;
      case M3EHapticLevel.none:
        break;
    }
  }

  void _onTapDown(TapDownDetails details) {
    _isPressed = true;
    _triggerHaptic();
    widget.neighborNotifier?.setPressed(true);

    _springSimulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 500, damping: 28),
      _controller.value,
      widget.scaleDown,
      _controller.velocity,
    );
    _controller.animateWith(_springSimulation);
    setState(() {});
  }

  void _onTapUp(TapUpDetails details) {
    widget.onTap();
    _rebound();
  }

  void _onTapCancel() {
    _rebound();
  }

  void _rebound() {
    _isPressed = false;
    widget.neighborNotifier?.setPressed(false);
    _springSimulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 500, damping: 28),
      _controller.value,
      1.0,
      _controller.velocity,
    );
    _controller.animateWith(_springSimulation);
    setState(() {});
  }

  BorderRadius _getCurrentRadius() {
    if (widget.restBorderRadius == null || widget.pressedBorderRadius == null) {
      return widget.restBorderRadius ?? BorderRadius.zero;
    }
    final t = (1.0 - _controller.value) / (1.0 - widget.scaleDown);
    final clampedT = t.clamp(0.0, 1.0);
    return BorderRadius.lerp(widget.restBorderRadius, widget.pressedBorderRadius, clampedT)!;
  }

  BoxDecoration? _getVariantDecoration(ColorScheme scheme) {
    if (widget.variant == null && widget.restBorderRadius == null) return null;
    Color color = Colors.transparent;
    
    if (widget.variant != null) {
      switch (widget.variant!) {
        case M3EButtonVariant.filled:
          color = scheme.primary;
          break;
        case M3EButtonVariant.filledTonal:
          color = scheme.secondaryContainer;
          break;
        case M3EButtonVariant.elevated:
          color = scheme.surfaceContainerLow;
          break;
        case M3EButtonVariant.outlined:
        case M3EButtonVariant.text:
          color = Colors.transparent;
          break;
      }
    }
    
    BoxBorder? border;
    if (widget.variant == M3EButtonVariant.outlined) {
      border = Border.all(color: scheme.outline);
    }
    
    return BoxDecoration(
      color: color,
      border: border,
      borderRadius: widget.restBorderRadius != null ? _getCurrentRadius() : null,
      boxShadow: widget.variant == M3EButtonVariant.elevated ? [
        BoxShadow(color: scheme.shadow.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))
      ] : null,
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget content = widget.child;
    
    content = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 300, end: _isPressed ? 500 : 300),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, weight, child) {
         return IconTheme(
           data: IconTheme.of(context).copyWith(weight: weight),
           child: child!,
         );
      },
      child: content,
    );
    
    if (widget.variant != null) {
      Color contentColor = scheme.primary;
      switch (widget.variant!) {
        case M3EButtonVariant.filled:
          contentColor = scheme.onPrimary;
          break;
        case M3EButtonVariant.filledTonal:
          contentColor = scheme.onSecondaryContainer;
          break;
        case M3EButtonVariant.elevated:
        case M3EButtonVariant.outlined:
        case M3EButtonVariant.text:
          contentColor = scheme.primary;
          break;
      }
      
      content = DefaultTextStyle(
         style: Theme.of(context).textTheme.labelLarge!.copyWith(color: contentColor),
         child: IconTheme(
           data: IconTheme.of(context).copyWith(color: contentColor),
           child: content,
         ),
      );
      
      content = Padding(
        padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: content,
      );
    }
    
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          double lateralSquish = 1.0;
          if (_neighborPressed && !_isPressed) {
            lateralSquish = 0.96;
          }
          
          return Transform.scale(
            scale: _controller.value,
            child: Transform.scale(
              scaleX: lateralSquish,
              child: Container(
                clipBehavior: widget.restBorderRadius != null ? Clip.antiAlias : Clip.none,
                decoration: _getVariantDecoration(scheme),
                child: _buildContent(context),
              )
            ),
          );
        },
      ),
    );
  }
}
