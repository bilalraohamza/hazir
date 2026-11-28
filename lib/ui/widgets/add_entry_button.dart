import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';

const _buttonHeight = 56.0;

class AddEntryButton extends StatelessWidget {
  const AddEntryButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return SizedBox.square(
      dimension: _buttonHeight,
      child: FloatingActionButton(
        heroTag: null,
        tooltip: 'Add entry',
        backgroundColor: colors.brass,
        foregroundColor: colors.onBrass,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: onPressed,
        child: const PhosphorIcon(PhosphorIconsRegular.plus),
      ),
    );
  }
}

class AddEntryScaffold extends StatefulWidget {
  const AddEntryScaffold({
    super.key,
    required this.appBar,
    required this.onAdd,
    this.scrollKey,
    this.slivers = const [],
    this.fillRemaining,
  });

  final PreferredSizeWidget appBar;
  final VoidCallback onAdd;
  final Key? scrollKey;
  final List<Widget> slivers;
  final Widget? fillRemaining;

  @override
  State<AddEntryScaffold> createState() => _AddEntryScaffoldState();
}

class _AddEntryScaffoldState extends State<AddEntryScaffold> {
  bool _visible = true;
  ScrollDirection _direction = ScrollDirection.idle;

  @override
  void didUpdateWidget(AddEntryScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollKey != widget.scrollKey) {
      _direction = ScrollDirection.idle;
      _visible = true;
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      _direction = notification.direction;
    }

    if (_direction == ScrollDirection.forward ||
        notification.metrics.extentBefore == 0) {
      _setVisible(true);
    } else if (_direction == ScrollDirection.reverse) {
      _setVisible(false);
    }
    return false;
  }

  void _setVisible(bool visible) {
    if (_visible != visible) setState(() => _visible = visible);
  }

  @override
  Widget build(BuildContext context) {
    // The tab bar consumes MediaQuery's bottom padding before building its pages.
    final view = View.of(context);
    final systemBottom = view.viewPadding.bottom / view.devicePixelRatio;
    final clearance =
        _buttonHeight + kFloatingActionButtonMargin + systemBottom;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final target = _visible ? 0.0 : 1.0;
    return ClipRect(
      child: Scaffold(
        appBar: widget.appBar,
        floatingActionButton: ExcludeSemantics(
          excluding: !_visible,
          child: IgnorePointer(
            ignoring: !_visible,
            child: TweenAnimationBuilder<double>(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              tween: Tween(end: target),
              child: AddEntryButton(onPressed: widget.onAdd),
              builder: (context, animation, child) {
                final slide = reducedMotion ? target : animation;
                return Transform.translate(
                  offset: Offset(0, clearance * slide),
                  child: Visibility.maintain(visible: slide < 1, child: child!),
                );
              },
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: CustomScrollView(
              key: widget.scrollKey,
              slivers: [
                ...widget.slivers,
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: clearance),
                    child: widget.fillRemaining ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
