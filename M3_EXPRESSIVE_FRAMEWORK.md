# Material 3 Expressive — Android App Framework
> Drop this file into any AI tool (Claude Code, Codex, Cursor, Antigravity, etc.)  
> and reference it in your prompts: "Follow M3_EXPRESSIVE_FRAMEWORK.md"

---

## 0 · What This Is

This is a complete, opinionated implementation framework for building Android apps that fully comply with the **Material 3 Expressive** design system — Google's 2025 evolution of Material You (Android 16 / QPR1). It covers:

- Color system (dynamic + seed + tonal palettes)
- Typography (baseline + emphasized dual scale)
- Shape system (35-token morphing library)
- Motion (spring-physics, spatial vs. effect tokens)
- Every core component with correct token usage
- Adaptive layouts (phone → tablet → desktop)
- Accessibility mandates
- Jetpack Compose implementation patterns
- Flutter implementation patterns

**Stack choices enforced by this framework:**
- Android: Jetpack Compose + `androidx.compose.material3` (BOM 2025.06.00+)
- Flutter: `flutter/material.dart` with `useMaterial3: true` (Flutter 3.16+)

---

## 1 · Project Bootstrap

### 1A · Android (Jetpack Compose)

**`build.gradle.kts` (app)**
```kotlin
dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.06.00")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3:material3-window-size-class")
    implementation("androidx.compose.material3:material3-adaptive-navigation-suite")
    implementation("com.google.android.material:material:1.12.0") // dynamic color bridge
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.core:core-splashscreen:1.0.1")
}
```

**`AndroidManifest.xml`** — required for dynamic color:
```xml
<application
    android:theme="@style/Theme.App.Starting"
    ...>
```

**`res/values/themes.xml`**
```xml
<resources>
    <style name="Theme.App.Starting" parent="Theme.SplashScreen">
        <item name="windowSplashScreenBackground">@color/md_theme_background</item>
        <item name="postSplashScreenTheme">@style/Theme.App</item>
    </style>
    <style name="Theme.App" parent="Theme.Material3.DayNight.NoActionBar"/>
</resources>
```

### 1B · Flutter

**`pubspec.yaml`**
```yaml
dependencies:
  flutter:
    sdk: flutter
  dynamic_color: ^1.8.1        # Material You wallpaper colors
  google_fonts: ^6.2.1         # Roboto Flex variable font
  flutter_animate: ^4.5.0      # Spring-physics animation helpers
```

**`main.dart` — minimal bootstrap**
```dart
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const _seedColor = Color(0xFF6750A4); // Replace with brand seed

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightScheme = lightDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _seedColor);
        final darkScheme = darkDynamic?.harmonized() ??
            ColorScheme.fromSeed(
              seedColor: _seedColor,
              brightness: Brightness.dark,
            );
        return MaterialApp(
          theme: _buildTheme(lightScheme),
          darkTheme: _buildTheme(darkScheme),
          themeMode: ThemeMode.system,
          home: const RootScreen(),
        );
      },
    );
  }

  ThemeData _buildTheme(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        textTheme: M3ExpressiveTypography.textTheme,
        // All component themes declared in Section 5
      );
}
```

---

## 2 · Color System

### 2A · Roles (always use tokens, never hex)

| Role | Light usage | Dark usage |
|------|-------------|------------|
| `primary` | Key actions, selected states | Same |
| `onPrimary` | Text/icons on primary | Same |
| `primaryContainer` | Prominent chips, cards | Same |
| `onPrimaryContainer` | Content in primary containers | Same |
| `secondary` | Less prominent UI | Same |
| `secondaryContainer` | Unselected nav items | Same |
| `tertiary` | Contrasting accents | Same |
| `tertiaryContainer` | Complementary surfaces | Same |
| `surface` | Default backgrounds | Same |
| `surfaceVariant` | Card/chip backgrounds | Same |
| `surfaceContainer` | Sheets, dialogs, nav drawers | Same |
| `surfaceContainerHigh` | Higher-emphasis surfaces | Same |
| `surfaceContainerHighest` | Highest-contrast surfaces | Same |
| `outline` | Borders, dividers | Same |
| `outlineVariant` | Subtle separators | Same |
| `error` / `onError` / `errorContainer` | Error states | Same |
| `inverseSurface` / `inverseOnSurface` | Snackbars | Same |
| `inversePrimary` | Tinted toolbar on dark | Same |
| `scrim` | Modals, overlays | Same |

### 2B · Tonal Palette Levels

M3 Expressive expanded the tonal palette. Each hue has tones:
`0, 4, 6, 10, 12, 17, 20, 22, 24, 30, 40, 50, 60, 70, 80, 87, 90, 92, 94, 95, 96, 98, 99, 100`

**Rule:** Never hardcode tone values. Use ColorScheme roles above.

### 2C · Android (Compose) Color Usage

```kotlin
// ✅ Always pull from MaterialTheme
val cs = MaterialTheme.colorScheme

Surface(color = cs.surface) { /* … */ }
Text(color = cs.onSurface)
Button(colors = ButtonDefaults.buttonColors()) // auto-uses primary
Icon(tint = cs.primary)

// ❌ Never do this
Box(modifier = Modifier.background(Color(0xFF6750A4)))
```

### 2D · Flutter Color Usage

```dart
// ✅ Correct
final cs = Theme.of(context).colorScheme;
Container(color: cs.surface)
Text('Hello', style: TextStyle(color: cs.onSurface))

// ❌ Wrong
Container(color: const Color(0xFF6750A4))
```

### 2E · Dynamic Color (Android 12+)

```kotlin
// In Activity.onCreate()
DynamicColorsCompat.applyToActivitiesIfAvailable(application)

// Or per-Activity:
DynamicColorsCompat.applyToActivityIfAvailable(this)
```

With a custom seed fallback:
```kotlin
val dynamicColorSource = DynamicColorsOptions.Builder()
    .setContentBasedSource(wallpaperColorSource)
    .build()
```

---

## 3 · Typography

### 3A · M3 Expressive Type Scale

M3 Expressive introduces **two parallel 15-style scales** — Baseline and Emphasized.

**Baseline Scale (standard weight)**

| Token | Size | Weight | Line Height |
|-------|------|--------|-------------|
| `displayLarge` | 57sp | 400 | 64sp |
| `displayMedium` | 45sp | 400 | 52sp |
| `displaySmall` | 36sp | 400 | 44sp |
| `headlineLarge` | 32sp | 400 | 40sp |
| `headlineMedium` | 28sp | 400 | 36sp |
| `headlineSmall` | 24sp | 400 | 32sp |
| `titleLarge` | 22sp | 400 | 28sp |
| `titleMedium` | 16sp | 500 | 24sp |
| `titleSmall` | 14sp | 500 | 20sp |
| `bodyLarge` | 16sp | 400 | 24sp |
| `bodyMedium` | 14sp | 400 | 20sp |
| `bodySmall` | 12sp | 400 | 16sp |
| `labelLarge` | 14sp | 500 | 20sp |
| `labelMedium` | 12sp | 500 | 16sp |
| `labelSmall` | 11sp | 500 | 16sp |

**Emphasized Scale** — heavier weights for hero moments:

| Token | Weight | Use case |
|-------|--------|----------|
| `displayLargeEmphasized` | 700 | Hero numbers, splash |
| `headlineLargeEmphasized` | 700 | Screen titles |
| `headlineMediumEmphasized` | 700 | Card headers |
| `titleLargeEmphasized` | 700 | App bar title |
| `bodyLargeEmphasized` | 700 | Important body copy |

**Font:** Roboto Flex (variable font). Use weight axis (`wght`) and optionally width axis (`wdth`) for expressive motion feedback.

### 3B · Compose Typography Setup

```kotlin
val AppTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily(Font(R.font.roboto_flex)),
        fontWeight = FontWeight.Normal,
        fontSize = 57.sp,
        lineHeight = 64.sp,
        letterSpacing = (-0.25).sp,
    ),
    headlineLarge = TextStyle(
        fontFamily = FontFamily(Font(R.font.roboto_flex)),
        fontWeight = FontWeight.Normal,
        fontSize = 32.sp,
        lineHeight = 40.sp,
    ),
    // … all 15 tokens
)

// In Theme:
MaterialTheme(typography = AppTypography) { /* … */ }

// Usage:
Text("Title", style = MaterialTheme.typography.headlineMedium)
// Emphasized (manual for now until API stabilizes):
Text("Hero", style = MaterialTheme.typography.displayLarge.copy(fontWeight = FontWeight.Bold))
```

### 3C · Flutter Typography Setup

```dart
// In theme_data.dart
class M3ExpressiveTypography {
  static final textTheme = TextTheme(
    displayLarge: GoogleFonts.robotoFlex(
      fontSize: 57, fontWeight: FontWeight.w400, height: 64 / 57,
      letterSpacing: -0.25,
    ),
    displayMedium: GoogleFonts.robotoFlex(fontSize: 45, fontWeight: FontWeight.w400, height: 52 / 45),
    displaySmall: GoogleFonts.robotoFlex(fontSize: 36, fontWeight: FontWeight.w400, height: 44 / 36),
    headlineLarge: GoogleFonts.robotoFlex(fontSize: 32, fontWeight: FontWeight.w400, height: 40 / 32),
    headlineMedium: GoogleFonts.robotoFlex(fontSize: 28, fontWeight: FontWeight.w400, height: 36 / 28),
    headlineSmall: GoogleFonts.robotoFlex(fontSize: 24, fontWeight: FontWeight.w400, height: 32 / 24),
    titleLarge: GoogleFonts.robotoFlex(fontSize: 22, fontWeight: FontWeight.w400, height: 28 / 22),
    titleMedium: GoogleFonts.robotoFlex(fontSize: 16, fontWeight: FontWeight.w500, height: 24 / 16, letterSpacing: 0.15),
    titleSmall: GoogleFonts.robotoFlex(fontSize: 14, fontWeight: FontWeight.w500, height: 20 / 14, letterSpacing: 0.1),
    bodyLarge: GoogleFonts.robotoFlex(fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16, letterSpacing: 0.5),
    bodyMedium: GoogleFonts.robotoFlex(fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14, letterSpacing: 0.25),
    bodySmall: GoogleFonts.robotoFlex(fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12, letterSpacing: 0.4),
    labelLarge: GoogleFonts.robotoFlex(fontSize: 14, fontWeight: FontWeight.w500, height: 20 / 14, letterSpacing: 0.1),
    labelMedium: GoogleFonts.robotoFlex(fontSize: 12, fontWeight: FontWeight.w500, height: 16 / 12, letterSpacing: 0.5),
    labelSmall: GoogleFonts.robotoFlex(fontSize: 11, fontWeight: FontWeight.w500, height: 16 / 11, letterSpacing: 0.5),
  );
}

// Usage:
Text('Title', style: Theme.of(context).textTheme.headlineMedium)
```

---

## 4 · Shape System

### 4A · M3 Expressive Shape Tokens

35 shape tokens with morphing support. The primary shape families:

| Token | Corner Radius | Use case |
|-------|--------------|----------|
| `extraSmall` | 4dp | Chips, tooltips |
| `extraSmall.top` | top-only 4dp | Bottom sheets |
| `small` | 8dp | Buttons, text fields |
| `medium` | 12dp | Cards, dialogs |
| `large` | 16dp | Nav drawer, side sheets |
| `large.top` | top-only 16dp | Bottom sheet |
| `extraLarge` | 28dp | FAB, large cards |
| `full` | 50% (pill) | Chips, extended FAB |
| `none` | 0dp | Banners |

**New in M3 Expressive:** Shapes can morph between states. Buttons expand/contract. FABs transform to dialogs.

### 4B · Compose Shapes

```kotlin
val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

// In theme:
MaterialTheme(shapes = AppShapes) { /* … */ }

// Usage:
Card(shape = MaterialTheme.shapes.medium) { /* … */ }
Surface(shape = MaterialTheme.shapes.extraLarge) { /* … */ }

// Shape morphing (M3 Expressive):
val shape by animateShapeAsState(
    if (expanded) MaterialTheme.shapes.extraLarge else MaterialTheme.shapes.small
)
```

### 4C · Flutter Shapes

```dart
// In ThemeData:
ThemeData(
  useMaterial3: true,
  cardTheme: const CardTheme(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
)

// Shape morphing with AnimatedContainer:
AnimatedContainer(
  duration: Durations.medium2,
  curve: M3ExpressiveMotion.spatialExpressive,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(isExpanded ? 28 : 8),
    color: cs.primaryContainer,
  ),
)
```

---

## 5 · Components Reference

### 5A · Buttons

**Four variants — use by hierarchy:**

| Variant | Use when |
|---------|----------|
| `FilledButton` | Primary action, one per screen |
| `FilledTonalButton` | Secondary action |
| `OutlinedButton` | Alternative/cancel action |
| `TextButton` | Tertiary, inline |
| `ElevatedButton` | Needs separation from background |

**M3 Expressive addition:** Buttons can have spring-animated size changes on press.

```kotlin
// Compose
FilledButton(onClick = { /* … */ }) {
    Icon(Icons.Default.Send, contentDescription = null)
    Spacer(Modifier.width(8.dp))
    Text("Send")
}

// Expressive spring press effect:
val scale by animateFloatAsState(
    targetValue = if (pressed) 0.94f else 1f,
    animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy)
)
Box(Modifier.scale(scale)) {
    FilledButton(onClick = { /* … */ }) { Text("Press Me") }
}
```

```dart
// Flutter
FilledButton.icon(
  onPressed: () {},
  icon: const Icon(Icons.send),
  label: const Text('Send'),
)
```

### 5B · FAB (Floating Action Button)

M3 Expressive key feature: **FAB morphs into full-screen content** via container transform.

```kotlin
// Small / Regular / Large / Extended variants
FloatingActionButton(
    onClick = { /* … */ },
    containerColor = MaterialTheme.colorScheme.primaryContainer,
    contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
) {
    Icon(Icons.Default.Add, contentDescription = "Add")
}

ExtendedFloatingActionButton(
    text = { Text("New Item") },
    icon = { Icon(Icons.Default.Add, null) },
    onClick = { /* … */ },
    expanded = isScrolledToTop, // collapses on scroll
)
```

### 5C · Navigation

**Rule: Match navigation pattern to screen count & form factor.**

| Component | Use when |
|-----------|----------|
| `NavigationBar` | Phone, 3–5 destinations |
| `NavigationRail` | Tablet/landscape, 3–7 destinations |
| `NavigationDrawer` | Desktop/large tablet, many destinations |
| `NavigationSuite` (adaptive) | Auto-switches between all three |

```kotlin
// Compose — Adaptive (PREFERRED)
NavigationSuiteScaffold(
    navigationSuiteItems = {
        navItems.forEach { item ->
            item(
                icon = { Icon(item.icon, item.label) },
                label = { Text(item.label) },
                selected = currentDest == item.route,
                onClick = { navController.navigate(item.route) },
            )
        }
    }
) {
    // Screen content
}
```

```dart
// Flutter — NavigationBar (phone)
NavigationBar(
  selectedIndex: _selectedIndex,
  onDestinationSelected: (i) => setState(() => _selectedIndex = i),
  destinations: const [
    NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
    NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
  ],
)
```

### 5D · App Bar

```kotlin
// Compose — 4 variants
TopAppBar(title = { Text("Screen") })

MediumTopAppBar(title = { Text("Screen") })   // collapses on scroll

LargeTopAppBar(                                // hero title
    title = { Text("Screen") },
    scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
)

CenterAlignedTopAppBar(title = { Text("App Name") })
```

### 5E · Cards

```kotlin
// 3 variants
Card(modifier = Modifier.fillMaxWidth()) { /* … */ }          // filled
ElevatedCard(modifier = Modifier.fillMaxWidth()) { /* … */ }  // shadow
OutlinedCard(modifier = Modifier.fillMaxWidth()) { /* … */ }  // border

// M3 Expressive: cards can have spring entrance animations
LaunchedEffect(Unit) {
    animate(0f, 1f, animationSpec = spring(
        dampingRatio = Spring.DampingRatioLowBouncy,
        stiffness = Spring.StiffnessMediumLow
    )) { value, _ -> scale = value }
}
```

### 5F · Text Fields

```kotlin
// Filled (default)
OutlinedTextField(
    value = text,
    onValueChange = { text = it },
    label = { Text("Email") },
    leadingIcon = { Icon(Icons.Default.Email, null) },
    isError = emailError != null,
    supportingText = emailError?.let { { Text(it) } },
    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
)

// Outlined (higher emphasis)
TextField(value = text, onValueChange = { text = it }, label = { Text("Name") })
```

### 5G · Dialogs

```kotlin
AlertDialog(
    onDismissRequest = { showDialog = false },
    icon = { Icon(Icons.Default.Warning, null) },
    title = { Text("Confirm action") },
    text = { Text("This cannot be undone.") },
    confirmButton = {
        FilledButton(onClick = { /* confirm */ }) { Text("Confirm") }
    },
    dismissButton = {
        TextButton(onClick = { showDialog = false }) { Text("Cancel") }
    },
)
```

### 5H · Chips

```kotlin
// 4 types
AssistChip(onClick = { }, label = { Text("Help") }, leadingIcon = { /* … */ })
FilterChip(selected = active, onClick = { active = !active }, label = { Text("Filter") })
InputChip(selected = true, onClick = { }, label = { Text("Tag") }, onDismiss = { })
SuggestionChip(onClick = { }, label = { Text("Python") })
```

### 5I · Bottom Sheets

```kotlin
val sheetState = rememberModalBottomSheetState()

ModalBottomSheet(
    onDismissRequest = { showSheet = false },
    sheetState = sheetState,
    shape = MaterialTheme.shapes.large.copy(
        bottomStart = CornerSize(0.dp), bottomEnd = CornerSize(0.dp)
    ),
) {
    // Sheet content
    Spacer(Modifier.navigationBarsPadding())
}
```

### 5J · Sliders

```kotlin
// Standard
Slider(value = sliderVal, onValueChange = { sliderVal = it })

// Range
RangeSlider(
    value = rangeVal,
    onValueChange = { rangeVal = it },
    valueRange = 0f..100f,
    steps = 9,
)
```

### 5K · Switches, Checkboxes, Radio Buttons

```kotlin
Switch(checked = checked, onCheckedChange = { checked = it })
Checkbox(checked = checked, onCheckedChange = { checked = it })
RadioButton(selected = selected, onClick = { selected = true })
```

### 5L · Progress Indicators

```kotlin
// Indeterminate
LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
CircularProgressIndicator()

// Determinate
LinearProgressIndicator(progress = { 0.7f })
CircularProgressIndicator(progress = { 0.7f })
```

### 5M · Snackbars

```kotlin
val snackbarHostState = remember { SnackbarHostState() }

Scaffold(snackbarHost = { SnackbarHost(snackbarHostState) }) { padding ->
    LaunchedEffect(event) {
        snackbarHostState.showSnackbar(
            message = "Done",
            actionLabel = "Undo",
            duration = SnackbarDuration.Short,
        )
    }
}
```

### 5N · Lists

```kotlin
// M3 3-line list item
ListItem(
    headlineContent = { Text("Item Title") },
    supportingContent = { Text("Secondary line") },
    overlineContent = { Text("Overline") },
    leadingContent = { Icon(Icons.Default.Star, null) },
    trailingContent = { Icon(Icons.Default.ChevronRight, null) },
    modifier = Modifier.clickable { /* … */ },
)
```

---

## 6 · Motion System

### 6A · Spring Physics — M3 Expressive Core Principle

M3 Expressive replaces duration-curve easing with **spring physics**. All spatial animations (position, size, shape) must use springs.

**Two motion schemes:**

| Scheme | Damping | Bounce | Use case |
|--------|---------|--------|----------|
| **Expressive** (default) | Low (~0.4) | Noticeable | Hero moments, FABs, nav transitions |
| **Standard** | High (~0.8) | Minimal | Utility UI, form interactions |

**Two token categories:**

| Category | Animates | Overshoot |
|----------|----------|-----------|
| **Spatial** | position, size, shape, scale | YES — spring bounce |
| **Effect** | opacity, color, elevation | NO — dampened |

### 6B · Compose Motion Tokens

```kotlin
object M3ExpressiveMotion {

    // Spatial — Expressive (low damping, bouncy)
    val spatialExpressiveFastSpatial = spring<Float>(
        dampingRatio = 0.42f,
        stiffness = 1400f
    )
    val spatialExpressiveDefaultSpatial = spring<Float>(
        dampingRatio = 0.42f,
        stiffness = 700f
    )
    val spatialExpressiveSlowSpatial = spring<Float>(
        dampingRatio = 0.42f,
        stiffness = 300f
    )

    // Spatial — Standard (high damping, minimal bounce)
    val spatialStandardFast = spring<Float>(
        dampingRatio = Spring.DampingRatioNoBouncy,
        stiffness = Spring.StiffnessMediumLow
    )

    // Effect — color/opacity (no overshoot ever)
    val effectFast = tween<Float>(durationMillis = 100, easing = LinearOutSlowInEasing)
    val effectDefault = tween<Float>(durationMillis = 200, easing = FastOutSlowInEasing)
    val effectSlow = tween<Float>(durationMillis = 300, easing = FastOutSlowInEasing)
}

// Usage:
val offsetX by animateFloatAsState(
    targetValue = if (active) 0f else -300f,
    animationSpec = M3ExpressiveMotion.spatialExpressiveDefaultSpatial,
)

val alpha by animateFloatAsState(
    targetValue = if (visible) 1f else 0f,
    animationSpec = M3ExpressiveMotion.effectDefault, // effect = no bounce
)
```

### 6C · Flutter Motion Tokens

```dart
class M3ExpressiveMotion {
  // Spatial Expressive
  static const spatialExpressiveFast = SpringDescription(mass: 1, stiffness: 1400, damping: 42);
  static const spatialExpressiveDefault = SpringDescription(mass: 1, stiffness: 700, damping: 33);
  static const spatialExpressiveSlow = SpringDescription(mass: 1, stiffness: 300, damping: 24);

  // Effect (no bounce — use Curves instead)
  static const effectFast = Duration(milliseconds: 100);
  static const effectDefault = Duration(milliseconds: 200);
  static const effectSlow = Duration(milliseconds: 300);
  static const effectCurve = Curves.easeInOutCubicEmphasized;
}

// Spatial animation (uses spring, may overshoot):
AnimationController ctrl = AnimationController.unbounded(vsync: this);
ctrl.animateWith(SpringSimulation(
  M3ExpressiveMotion.spatialExpressiveDefault,
  from, to, velocity,
));

// Effect animation (uses curve, never overshoots):
AnimatedOpacity(
  opacity: visible ? 1.0 : 0.0,
  duration: M3ExpressiveMotion.effectDefault,
  curve: M3ExpressiveMotion.effectCurve,
  child: child,
)
```

### 6D · Transition Patterns

```kotlin
// Shared Axis (navigate between related screens)
AnimatedContent(
    targetState = currentScreen,
    transitionSpec = {
        slideInHorizontally(
            animationSpec = M3ExpressiveMotion.spatialExpressiveDefaultSpatial
        ) togetherWith slideOutHorizontally(
            animationSpec = M3ExpressiveMotion.spatialExpressiveDefaultSpatial
        )
    }
) { screen -> /* render screen */ }

// Container Transform (element → full screen)
// Use Accompanist Navigation Animation or Compose shared element transitions
SharedTransitionLayout {
    AnimatedContent(targetState = selectedItem) { item ->
        if (item == null) {
            // List: mark source element
            Card(modifier = Modifier.sharedElement(
                rememberSharedContentState(key = "card"),
                animatedVisibilityScope = this@AnimatedContent
            )) { /* list item */ }
        } else {
            // Detail: mark destination
            Surface(modifier = Modifier.sharedElement(
                rememberSharedContentState(key = "card"),
                animatedVisibilityScope = this@AnimatedContent
            )) { /* detail screen */ }
        }
    }
}

// Fade Through (unrelated screens)
AnimatedContent(
    transitionSpec = {
        fadeIn(animationSpec = M3ExpressiveMotion.effectDefault) +
        scaleIn(initialScale = 0.92f) togetherWith
        fadeOut(animationSpec = M3ExpressiveMotion.effectFast)
    }
) { /* … */ }
```

---

## 7 · Layout & Adaptive Design

### 7A · Window Size Classes

```kotlin
val windowSizeClass = calculateWindowSizeClass(this)

when (windowSizeClass.widthSizeClass) {
    WindowWidthSizeClass.Compact -> PhoneLayout()    // < 600dp
    WindowWidthSizeClass.Medium -> TabletLayout()    // 600–839dp
    WindowWidthSizeClass.Expanded -> DesktopLayout() // ≥ 840dp
}
```

### 7B · Spacing Scale (8dp grid)

| Token | Value | Use |
|-------|-------|-----|
| `extraSmall` | 4dp | Icon internal padding |
| `small` | 8dp | Component internal padding |
| `medium` | 16dp | Screen horizontal margin |
| `large` | 24dp | Section spacing |
| `extraLarge` | 32dp | Hero sections |
| `giant` | 48dp | Display spacing |

```kotlin
object Spacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 16.dp
    val lg = 24.dp
    val xl = 32.dp
    val xxl = 48.dp
}
```

### 7C · Scaffold Template (Compose)

```kotlin
@Composable
fun AppScaffold(
    navController: NavHostController,
    content: @Composable (PaddingValues) -> Unit,
) {
    val windowSizeClass = calculateWindowSizeClass(LocalContext.current as Activity)
    
    NavigationSuiteScaffold(
        navigationSuiteItems = {
            TopLevelRoute.entries.forEach { route ->
                item(
                    icon = { Icon(route.icon, route.title) },
                    label = { Text(route.title) },
                    selected = navController.currentDestinationIs(route),
                    onClick = { navController.navigateTo(route) },
                )
            }
        },
    ) {
        Scaffold(
            topBar = {
                LargeTopAppBar(
                    title = { Text(currentTitle) },
                    scrollBehavior = scrollBehavior,
                )
            },
            floatingActionButton = {
                ExtendedFloatingActionButton(
                    text = { Text("New") },
                    icon = { Icon(Icons.Default.Add, null) },
                    onClick = { /* … */ },
                    expanded = !isScrolling,
                )
            },
            contentWindowInsets = WindowInsets.safeDrawing,
        ) { padding ->
            content(padding)
        }
    }
}
```

### 7D · Edge-to-Edge (Required for M3 Expressive)

```kotlin
// In Activity.onCreate():
enableEdgeToEdge()

// In Compose, consume insets:
Scaffold(
    contentWindowInsets = WindowInsets.safeDrawing,
) { padding ->
    Column(Modifier.padding(padding)) { /* … */ }
}

// Or manually:
Modifier
    .windowInsetsPadding(WindowInsets.systemBars)
    .windowInsetsPadding(WindowInsets.displayCutout)
```

---

## 8 · Elevation & Surface

### 8A · Tonal Elevation Levels

M3 Expressive uses color tinting instead of only shadows:

| Level | dp | Surface tint opacity |
|-------|----|----------------------|
| 0 | 0dp | 0% |
| 1 | 1dp | 5% |
| 2 | 3dp | 8% |
| 3 | 6dp | 11% (dialogs, sheets) |
| 4 | 8dp | 12% (nav drawers) |
| 5 | 12dp | 14% (modals) |

```kotlin
Surface(
    shadowElevation = 3.dp,
    tonalElevation = 3.dp,   // adds color tint
    color = MaterialTheme.colorScheme.surface,
) { /* … */ }

Card(elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)) { /* … */ }
ElevatedCard(elevation = CardDefaults.elevatedCardElevation(defaultElevation = 6.dp)) { /* … */ }
```

---

## 9 · Accessibility

### 9A · Non-negotiable rules

1. **Touch targets** ≥ 48×48dp for all interactive elements
2. **Color contrast**: 4.5:1 for body text (AA), 3:1 for large text
3. **Never convey info by color alone** — always add icon/text/pattern
4. **Content descriptions** on all icon-only actions
5. **Semantic roles** on custom components
6. **Text scaling** — test at 200% font scale, never clamp text sizes
7. **Keyboard navigation** — all actions reachable without touch

```kotlin
// Touch target enforcement:
Icon(
    Icons.Default.Delete,
    contentDescription = "Delete item",
    modifier = Modifier
        .size(24.dp)
        .minimumInteractiveComponentSize() // Ensures 48dp touch target
)

// Semantic roles:
Box(
    modifier = Modifier
        .semantics {
            role = Role.Button
            contentDescription = "Play video"
            onClick { onPlay(); true }
        }
)

// Large text must wrap, never ellipsize for critical info:
Text(
    text = label,
    overflow = TextOverflow.Ellipsis,
    maxLines = 2, // Allow 2 lines for accessibility scaling
)
```

### 9B · Dynamic contrast (M3 Expressive)

```kotlin
// Support high-contrast mode
val isHighContrast = LocalContext.current
    .getSystemService(AccessibilityManager::class.java)
    ?.isHighTextContrastEnabled == true

val textColor = if (isHighContrast)
    MaterialTheme.colorScheme.onSurface
else
    MaterialTheme.colorScheme.onSurfaceVariant
```

---

## 10 · Theme File — Complete Compose Setup

```kotlin
// ui/theme/Theme.kt
@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context)
            else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        shapes = AppShapes,
        content = content,
    )
}

// Seed-based fallback schemes:
private val LightColorScheme = ColorScheme.fromSeed(
    seedColor = BrandSeed,
    // Generated via Material Theme Builder
)

private val DarkColorScheme = ColorScheme.fromSeed(
    seedColor = BrandSeed,
    brightness = Brightness.dark,
)
```

---

## 11 · AI Prompt Patterns (How to Use This Framework)

When using this file in Claude Code, Codex, Cursor, or any AI tool:

### Pattern A — New screen
```
Using M3_EXPRESSIVE_FRAMEWORK.md, create a Flutter/Compose screen for [purpose].
Requirements:
- Use NavigationBar for 3 destinations
- LargeTopAppBar with exitUntilCollapsed scroll behavior
- CardList with container transform to detail
- All colors from ColorScheme tokens, no hardcoded hex
- Spring animations for spatial transitions, tween for opacity/color
```

### Pattern B — Component request
```
Following M3_EXPRESSIVE_FRAMEWORK.md Section 5 component specs:
Build a product card that:
- Uses ElevatedCard with medium shape (12dp)
- Has a spring-animated scale on press (dampingRatio: 0.42, stiffness: 700)
- Title: headlineMedium, body: bodyMedium, price: titleLarge emphasized
- All colors from colorScheme tokens
```

### Pattern C — Full app scaffold
```
Using M3_EXPRESSIVE_FRAMEWORK.md, generate a complete app scaffold:
- Adaptive navigation (NavigationBar on phone, NavigationRail on tablet)
- Edge-to-edge with WindowInsets.safeDrawing
- Dynamic color from Android 12+ wallpaper with seed fallback
- 3 destinations: Home, Search, Profile
- ExtendedFloatingActionButton that collapses on scroll
```

### Pattern D — Animation review
```
Review this Compose animation against M3_EXPRESSIVE_FRAMEWORK.md Section 6:
[paste code]
Check:
1. Are spatial animations using spring specs?
2. Are color/opacity transitions using tween (no bounce)?
3. Is transition type correct (sharedAxis/containerTransform/fadeThrough)?
```

### Pattern E — Theme audit
```
Audit this component against M3_EXPRESSIVE_FRAMEWORK.md:
[paste code]
Flag any:
- Hardcoded colors (should use MaterialTheme.colorScheme.*)
- Hardcoded font sizes (should use MaterialTheme.typography.*)
- Touch targets < 48dp
- Missing content descriptions
```

---

## 12 · Quick Reference Cheat Sheet

```
COLOR     → MaterialTheme.colorScheme.[role]
           Never: Color(0xFF...)

TYPOGRAPHY → MaterialTheme.typography.[scale]
            Never: fontSize = 16.sp standalone

SHAPE     → MaterialTheme.shapes.[size]
            Never: RoundedCornerShape(12.dp) inline

MOTION    → Spatial (position/size/shape) = spring(), may bounce
            Effect (color/alpha/elev) = tween(), no bounce
            Expressive = dampingRatio ~0.42 (bouncy)
            Standard  = dampingRatio ~0.8  (calm)

SPACING   → 4 / 8 / 16 / 24 / 32 / 48 dp grid only

ELEVATION → 0 / 1 / 3 / 6 / 8 / 12 dp levels only
            Use tonalElevation for color tint

TOUCH     → Minimum 48×48dp for all interactive elements

INSETS    → Always: contentWindowInsets = WindowInsets.safeDrawing
            Never clip content behind system bars

ADAPTIVE  → Compact < 600dp  → NavigationBar
            Medium  600–840dp → NavigationRail
            Expanded > 840dp  → NavigationDrawer
```

---

## 13 · Checklist — Before Shipping Any Screen

- [ ] All colors reference `colorScheme` tokens
- [ ] All text uses `typography` scale tokens
- [ ] All shapes use `shapes` tokens or declared constants
- [ ] Spatial animations use spring specs
- [ ] Effect animations use tween/no-bounce specs
- [ ] Edge-to-edge enabled with proper inset handling
- [ ] All icon buttons have `contentDescription`
- [ ] Touch targets ≥ 48dp on all interactive elements
- [ ] Adaptive navigation responds to window size class
- [ ] Dark mode tested
- [ ] 200% font scale tested (no content clipped)
- [ ] Dynamic color tested on Android 12+ device/emulator

---

*Framework version: 2025.2 — aligned with Material 3 Expressive (Android 16 / QPR1)*  
*References: m3.material.io · developer.android.com/develop/ui/compose/designsystems/material3*
