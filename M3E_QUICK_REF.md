# M3 Expressive — Quick Reference Card
> Paste into any AI chat. Say: "Use this M3E reference for all UI code."

## Color — Always token, never hex
```kotlin
// Compose
MaterialTheme.colorScheme.primary / onPrimary / primaryContainer / onPrimaryContainer
MaterialTheme.colorScheme.secondary / tertiary / surface / surfaceContainer
MaterialTheme.colorScheme.outline / outlineVariant / error / scrim

// Flutter
Theme.of(context).colorScheme.primary   // same role names
```

## Typography
```kotlin
// Compose: displayLarge/Medium/Small · headlineLarge/Medium/Small
//          titleLarge/Medium/Small   · bodyLarge/Medium/Small
//          labelLarge/Medium/Small
MaterialTheme.typography.headlineMedium   // use this
TextStyle(fontSize = 28.sp)               // ❌ never this

// Emphasized (heavier, hero moments):
MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold)
```

## Shapes
```kotlin
// extraSmall=4dp · small=8dp · medium=12dp · large=16dp · extraLarge=28dp · full=pill
MaterialTheme.shapes.medium   // ✅
RoundedCornerShape(12.dp)     // ❌ inline hardcode
```

## Motion — THE KEY RULE
```
Spatial (move/resize/morph) → spring() — CAN bounce
Effect  (color/opacity)     → tween()  — NEVER bounce

Expressive spring: dampingRatio=0.42, stiffness=700  ← default for M3E
Standard   spring: dampingRatio=0.8,  stiffness=700  ← calm utility UI
```
```kotlin
// Spatial (position, size, shape):
animateFloatAsState(targetValue, spring(dampingRatio=0.42f, stiffness=700f))

// Effect (opacity, color):
animateFloatAsState(targetValue, tween(200, easing=FastOutSlowInEasing))
```

## Components — Correct Variants
```
Primary action    → FilledButton
Secondary action  → FilledTonalButton
Tertiary/cancel   → TextButton / OutlinedButton

Phone nav         → NavigationBar (3-5 destinations)
Tablet nav        → NavigationRail
Large tablet/desk → NavigationDrawer
Auto-adaptive     → NavigationSuiteScaffold ← PREFER THIS

Screen title      → LargeTopAppBar + exitUntilCollapsedScrollBehavior
Modal overlay     → ModalBottomSheet
Confirmation      → AlertDialog
Feedback          → Snackbar (not Toast)
```

## Adaptive Breakpoints
```
< 600dp  Compact  → phone portrait
600-840dp Medium  → tablet portrait / phone landscape
> 840dp  Expanded → tablet landscape / desktop
```

## Elevation Levels
```
0dp · 1dp · 3dp · 6dp · 8dp · 12dp  (use tonalElevation for color tint)
```

## Spacing Grid (8dp base)
```
4 / 8 / 16 / 24 / 32 / 48 dp
```

## Accessibility Non-negotiables
```
Touch targets: min 48×48dp (.minimumInteractiveComponentSize())
Contrast: 4.5:1 body text, 3:1 large text
contentDescription on all icon-only buttons
Insets: WindowInsets.safeDrawing, enableEdgeToEdge()
```

## Transition Types
```
Related screens (drill-down)   → Shared Axis (slide)
Element → Full screen          → Container Transform
Unrelated destinations         → Fade Through
```
