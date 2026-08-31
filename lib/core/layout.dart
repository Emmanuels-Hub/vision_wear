import 'package:flutter/material.dart';

/// Screen-size buckets, following the Material window-size classes.
enum WindowSize {
  /// Phones in portrait. The design target.
  compact,

  /// Large phones in landscape, small tablets.
  medium,

  /// Tablets and desktop windows.
  expanded,
}

/// Layout rules, in one place so screens do not each invent their own
/// breakpoints.
///
/// Two things drive the layout here, and they are not the same question:
///   * **Width** decides how much content fits side by side, and whether a
///     single column of full-bleed buttons starts looking absurd.
///   * **Height** decides whether a camera preview and its info panel can be
///     stacked at all. A phone in landscape is wide but very short, so the
///     vision screen has to put them side by side or the panel is unusable.
class Layout {
  Layout._();

  static const double mediumBreakpoint = 600;
  static const double expandedBreakpoint = 900;

  /// Beyond this, content is centred rather than stretched. A 64px-tall button
  /// spanning a 1200px window is not more accessible, just stranger.
  static const double maxContentWidth = 680;

  /// Below this the vision screen switches to a side-by-side layout, because
  /// a stacked camera and panel would each get a useless sliver of height.
  static const double minStackedHeight = 520;

  static const double gutterCompact = 16;
  static const double gutterExpanded = 24;
}

extension LayoutX on BuildContext {
  Size get _screen => MediaQuery.sizeOf(this);

  WindowSize get windowSize {
    final width = _screen.width;
    if (width >= Layout.expandedBreakpoint) return WindowSize.expanded;
    if (width >= Layout.mediumBreakpoint) return WindowSize.medium;
    return WindowSize.compact;
  }

  bool get isCompact => windowSize == WindowSize.compact;
  bool get isExpanded => windowSize == WindowSize.expanded;

  /// True when the camera feed and its panel should sit side by side rather
  /// than stacked. Driven by available height, not orientation, so a tall
  /// tablet in landscape still stacks.
  bool get prefersSideBySide =>
      _screen.height < Layout.minStackedHeight ||
      _screen.width >= Layout.expandedBreakpoint;

  /// Standard page padding for the current width.
  EdgeInsets get pagePadding => EdgeInsets.all(
        isCompact ? Layout.gutterCompact : Layout.gutterExpanded,
      );

  /// How many columns a grid of action buttons should use.
  int get actionColumns => switch (windowSize) {
        WindowSize.compact => 1,
        WindowSize.medium => 2,
        WindowSize.expanded => 2,
      };
}

/// Centres and width-limits a screen's body, and applies the standard padding.
///
/// Wrap the body of any scrolling screen in this rather than padding it by
/// hand, so every screen agrees about margins and about how wide text is
/// allowed to get before it becomes hard to track across a line.
class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.child,
    this.maxWidth = Layout.maxContentWidth,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: padding ?? context.pagePadding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Lays children out in one column on a phone and a grid on anything wider.
///
/// Used for the home screen's action list: a single tall column of buttons is
/// right on a phone and wasteful on a tablet.
class ResponsiveActionGrid extends StatelessWidget {
  const ResponsiveActionGrid({
    super.key,
    required this.children,
    this.spacing = 12,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final columns = context.actionColumns;

    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }

    // Measure rather than assume: this sits inside a width-constrained page,
    // so the screen width is not the width available here.
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
