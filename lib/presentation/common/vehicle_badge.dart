import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/vehicle_type.dart';

/// Offline vector illustrations with distinct silhouettes, not just colors.
class VehicleBadge extends StatelessWidget {
  const VehicleBadge({super.key, required this.type, this.size = 88});
  final VehicleType type;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: type.label,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _VehiclePainter(type)),
    ),
  );
}

class _VehiclePainter extends CustomPainter {
  const _VehiclePainter(this.type);
  final VehicleType type;
  static const ink = AppColors.charcoal;
  static const glass = Color(0xFFB9E8FF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 120);
    final paint = Paint()..isAntiAlias = true;
    void box(
      double x,
      double y,
      double w,
      double h,
      Color color, [
      double radius = 2,
    ]) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(radius),
      );
      canvas.drawRRect(
        rect,
        paint
          ..style = PaintingStyle.fill
          ..color = color,
      );
      canvas.drawRRect(
        rect,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ink,
      );
    }

    void line(
      double x,
      double y,
      double x2,
      double y2, [
      Color color = ink,
      double width = 2.5,
    ]) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x2, y2),
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color
          ..strokeCap = StrokeCap.round,
      );
    }

    void wheel(double x, double y, double radius) {
      canvas.drawCircle(
        Offset(x, y),
        radius,
        paint
          ..style = PaintingStyle.fill
          ..color = ink,
      );
      canvas.drawCircle(
        Offset(x, y),
        radius * .48,
        paint..color = Colors.white,
      );
      canvas.drawCircle(Offset(x, y), radius * .2, paint..color = ink);
    }

    void cab(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.fill
          ..color = color,
      );
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = ink,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.5, 1.5, 117, 117),
        const Radius.circular(18),
      ),
      paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFFFF8DF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.5, 1.5, 117, 117),
        const Radius.circular(18),
      ),
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ink,
    );
    line(10, 99, 110, 99, const Color(0xFFD6CBA8), 4);
    switch (type) {
      case VehicleType.boleroPickup:
        box(53, 62, 55, 22, const Color(0xFFF5AE29));
        cab(const [
          Offset(13, 82),
          Offset(13, 66),
          Offset(24, 62),
          Offset(29, 45),
          Offset(50, 45),
          Offset(57, 82),
        ], Colors.white);
        box(30, 49, 18, 15, glass);
        box(12, 76, 16, 7, ink);
        // Rack above cab and long TMT rods projecting forward.
        line(27, 43, 27, 29);
        line(56, 62, 56, 29);
        line(24, 30, 60, 30, ink, 4);
        for (var y = 23.0; y <= 27; y += 4) {
          line(14, y, 105, y, const Color(0xFF5F6973), 3);
        }
        line(66, 66, 98, 66);
        wheel(33, 85, 11);
        wheel(92, 85, 11);
      case VehicleType.tataAce:
        box(49, 61, 58, 22, const Color(0xFF13AACC));
        cab(const [
          Offset(14, 83),
          Offset(14, 58),
          Offset(21, 44),
          Offset(44, 44),
          Offset(49, 83),
        ], Colors.white);
        box(21, 49, 20, 18, glass);
        box(12, 76, 14, 7, AppColors.amber);
        line(54, 68, 101, 68);
        wheel(31, 85, 10);
        wheel(91, 85, 10);
      case VehicleType.dost:
        box(54, 54, 54, 29, const Color(0xFFEF762E));
        cab(const [
          Offset(12, 83),
          Offset(15, 66),
          Offset(22, 62),
          Offset(27, 42),
          Offset(48, 42),
          Offset(55, 83),
        ], const Color(0xFF3689DA));
        box(29, 47, 16, 18, glass);
        box(9, 74, 22, 9, Colors.white);
        line(63, 62, 100, 62);
        line(63, 71, 100, 71);
        wheel(34, 86, 11);
        wheel(91, 86, 11);
      case VehicleType.eicher14ft:
        box(47, 40, 62, 43, const Color(0xFFEDA529));
        cab(const [
          Offset(10, 82),
          Offset(10, 41),
          Offset(17, 30),
          Offset(41, 30),
          Offset(47, 82),
        ], const Color(0xFFE64D3B));
        box(17, 36, 21, 22, glass);
        box(9, 72, 16, 10, Colors.white);
        line(50, 49, 106, 49);
        line(50, 62, 106, 62);
        for (var x = 57.0; x < 108; x += 12) {
          line(x, 40, x, 79);
        }
        wheel(29, 87, 11);
        wheel(82, 87, 11);
        wheel(101, 87, 11);
      case VehicleType.tractor:
        // Rear wheel is close to the trailer; bonnet faces left.
        box(75, 55, 35, 26, const Color(0xFFF0AB32));
        line(60, 81, 75, 81, ink, 4);
        box(13, 61, 31, 15, const Color(0xFF219B56));
        box(38, 43, 24, 36, const Color(0xFF219B56));
        box(41, 47, 17, 18, glass);
        box(35, 38, 30, 5, AppColors.amber);
        line(22, 61, 22, 48, ink, 4);
        box(10, 73, 12, 5, ink);
        line(81, 63, 104, 63);
        wheel(24, 85, 9);
        wheel(53, 82, 17);
        wheel(94, 85, 10);
        for (var angle = 0.0; angle < 6.28; angle += .785) {
          canvas.save();
          canvas.translate(53, 82);
          canvas.rotate(angle);
          line(0, -13, 5, -15, const Color(0xFF67756F), 2);
          canvas.restore();
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VehiclePainter oldDelegate) =>
      type != oldDelegate.type;
}
