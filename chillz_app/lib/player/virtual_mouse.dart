import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // For BoxHitTestResult
import 'package:flutter/services.dart';

/// Controller for the virtual mouse cursor
class VirtualMouseController extends ChangeNotifier {
  Offset _position = const Offset(100, 100);
  bool _isVisible = false;
  Size _screenSize = Size.zero;

  // Configuration
  double speed = 15.0; // Pixels per tick/move
  double acceleration = 1.2;

  bool get isVisible => _isVisible;
  Offset get position => _position;

  void setScreenSize(Size size) {
    _screenSize = size;
    // Reset position to center if it's currently 0,0 or out of bounds
    if (_position == const Offset(100, 100) || !_isWithinBounds(_position)) {
      _position = Offset(size.width / 2, size.height / 2);
    }
  }

  void toggleVisibility() {
    _isVisible = !_isVisible;
    if (_isVisible) {
      // Reset position to center when showing if needed,
      // or just keep last position.
      // _position = Offset(_screenSize.width / 2, _screenSize.height / 2);
    }
    notifyListeners();
  }

  void setVisible(bool visible) {
    _isVisible = visible;
    notifyListeners();
  }

  void move(double dx, double dy) {
    if (!_isVisible) return;

    // Apply acceleration if moving consistently (can be enhanced later)
    // For now just consistent movement
    final newPos = _position + Offset(dx * speed, dy * speed);

    if (_isWithinBounds(newPos)) {
      _position = newPos;
      notifyListeners();
    } else {
      // Clamp to screen
      _position = Offset(
        newPos.dx.clamp(0.0, _screenSize.width),
        newPos.dy.clamp(0.0, _screenSize.height),
      );
      notifyListeners();
    }
  }

  bool _isWithinBounds(Offset pos) {
    if (_screenSize == Size.zero) return true;
    return pos.dx >= 0 &&
        pos.dx <= _screenSize.width &&
        pos.dy >= 0 &&
        pos.dy <= _screenSize.height;
  }

  /// Simulate a click at the current cursor position
  void click() {
    if (!_isVisible) return;

    // We need to dispatch a pointer event to the system
    // This is tricky in Flutter without native support,
    // but we can try to hit test the widget tree or use global keys
    // if we want to trigger specific actions.
    // However, the best "virtual mouse" often actually needs to dispatch
    // a real tap event to the widget system.

    // Using WidgetsBinding to handle hit testing and dispatching
    // is the most robust way within Flutter widgets.

    final hitTestResult = BoxHitTestResult();
    WidgetsBinding.instance.hitTestInView(
        hitTestResult, _position, 0); // 0 is usually the default view ID

    // This approach (hitTestInView) might not dispatch events to standard GestureDetector/InkWell
    // if they don't explicitly listen to this flow, but standard simulation involves adding a pointer event.

    // Alternative: GestureBinding.instance.handlePointerEvent
    final addEvent = PointerAddedEvent(position: _position);
    final downEvent =
        PointerDownEvent(position: _position, buttons: kPrimaryButton);
    final upEvent = PointerUpEvent(position: _position);

    GestureBinding.instance.handlePointerEvent(addEvent);
    GestureBinding.instance.handlePointerEvent(downEvent);
    // Add a small delay for tap recognition? Usually handled immediately.
    GestureBinding.instance.handlePointerEvent(upEvent);
  }
}

/// Overlay widget that draws the cursor
class VirtualMouseOverlay extends StatelessWidget {
  final VirtualMouseController controller;
  final Widget child;

  const VirtualMouseOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Update screen size in controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        controller.setScreenSize(MediaQuery.of(context).size);
      }
    });

    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (!controller.isVisible) return const SizedBox.shrink();

            return Positioned(
              left: controller.position.dx,
              top: controller.position.dy,
              child: Transform.translate(
                offset: const Offset(-8, -5), // Center tip of pointer
                child: const MousePointer(
                  color: Colors.white,
                  borderColor: Colors.black,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class MousePointer extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final double size;

  const MousePointer({
    super.key,
    this.color = Colors.white,
    this.borderColor = Colors.black,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MousePointerPainter(
          color: color,
          borderColor: borderColor,
        ),
      ),
    );
  }
}

class _MousePointerPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _MousePointerPainter({
    required this.color,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    // Simple arrow shape
    path.moveTo(0, 0);
    path.lineTo(size.width * 0.7, size.height);
    path.lineTo(size.width * 0.4, size.height * 0.6);
    path.lineTo(0, size.height * 0.8);
    path.close();

    // Rotate slightly to look like a mouse cursor
    // Actually standard cursor leans left.
    // Let's draw a standard pointer shape.

    final cursorPath = Path();
    cursorPath.moveTo(0, 0);
    cursorPath.lineTo(0, size.height); // Down
    cursorPath.lineTo(size.width * 0.25, size.height * 0.75);
    cursorPath.lineTo(size.width * 0.6, size.height * 0.95); // Tail part 1
    cursorPath.lineTo(size.width * 0.75, size.height * 0.80); // Tail part 2
    cursorPath.lineTo(size.width * 0.4, size.height * 0.6);
    cursorPath.lineTo(size.width, size.height * 0.6); // Right
    cursorPath.close();

    // Standard arrow
    final arrowPath = Path();
    arrowPath.moveTo(0, 0);
    arrowPath.lineTo(size.width * 0.4, size.height); // Bottom point
    arrowPath.lineTo(size.width * 0.4, size.height * 0.55); // Inner corner
    arrowPath.lineTo(size.width * 0.9, size.height * 0.55); // Right wing
    arrowPath.close();

    canvas.save();
    canvas.rotate(-0.5); // Tilt
    canvas.translate(5, 5); // Adjust for tilt

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    // Use a standard simple triangle for now to be safe and clear
    final simplePath = Path();
    simplePath.moveTo(0, 0);
    simplePath.lineTo(0, 25);
    simplePath.lineTo(8, 20);
    simplePath.lineTo(14, 32);
    simplePath.lineTo(18, 30);
    simplePath.lineTo(12, 18);
    simplePath.lineTo(22, 18);
    simplePath.close();

    canvas.restore();

    // Draw without extra rotation for simplicity in coordinate alignment
    canvas.drawPath(simplePath, paint);
    canvas.drawPath(simplePath, borderPaint);

    // Dot at 0,0 for debugging precision
    // canvas.drawCircle(Offset.zero, 2, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
