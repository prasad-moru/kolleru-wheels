import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/localization/app_language_provider.dart';

class OnboardingIllustrationCard extends StatelessWidget {
  const OnboardingIllustrationCard({
    super.key,
    required this.step,
    this.language = AppLanguage.telugu,
  }) : assert(step >= 0 && step < 3);

  final int step;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: switch ((step, language)) {
      (0, AppLanguage.telugu) => 'చేపలు, రొయ్యల చెరువుల నుంచి రోడ్డు ద్వారా వాహనానికి',
      (0, _) => 'Fish and prawn ponds connected to a transport truck by road',
      (1, AppLanguage.telugu) => 'వాహన సామర్థ్యం, ధృవీకరించిన ఫోన్‌తో డ్రైవర్ కార్డులు',
      (1, _) => 'Driver cards with vehicle capacities and verified phone badges',
      (_, AppLanguage.telugu) => 'రైతు, డ్రైవర్ మధ్య నేరుగా ఫోన్, వాట్సాప్ పరిచయం',
      (_, _) => 'A farmer and driver connected directly by phone and WhatsApp',
    },
    child: Container(
      key: ValueKey('welcome-illustration-$step'),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4EA),
        border: Border.all(color: const Color(0xFFCEEAD6)),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 360 / 280,
        child: CustomPaint(
          painter: _AquaIllustrationPainter(step: step, language: language),
        ),
      ),
    ),
  );
}

class _AquaIllustrationPainter extends CustomPainter {
  const _AquaIllustrationPainter({required this.step, required this.language});
  final int step;
  final AppLanguage language;
  static const _green = Color(0xFF0F5132);
  static const _mint = Color(0xFF95D5B2);
  static const _ink = Color(0xFF244B3B);
  static const _amber = Color(0xFFD97706);

  String _tr(String te, String en) => language == AppLanguage.telugu ? te : en;

  Paint _paint(Color color) => Paint()..color = color;

  void _box(Canvas canvas, Rect rect, Color color, [double radius = 12]) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), _paint(color));
  }

  void _line(Canvas canvas, Path path, Color color, [double width = 3]) {
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  void _text(Canvas canvas, String text, Offset at, {double size = 12, Color color = _ink, double width = 140}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(
        color: color, fontSize: size, fontWeight: FontWeight.w600,
      )),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: width);
    painter.paint(canvas, at);
    painter.dispose();
  }

  void _check(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 13, _paint(_green));
    _line(canvas, Path()
      ..moveTo(center.dx - 5, center.dy)
      ..lineTo(center.dx - 1, center.dy + 4)
      ..lineTo(center.dx + 6, center.dy - 4), Colors.white, 2.5);
  }

  void _truck(Canvas canvas, Offset at, {double scale = 1}) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(scale);
    _box(canvas, const Rect.fromLTWH(0, 0, 76, 44), _green, 5);
    canvas.drawPath(Path()
      ..moveTo(79, 9)..lineTo(101, 9)..lineTo(119, 30)
      ..lineTo(119, 47)..lineTo(79, 47)..close(), _paint(const Color(0xFF36A377)));
    canvas.drawPath(Path()
      ..moveTo(85, 15)..lineTo(98, 15)..lineTo(109, 29)
      ..lineTo(85, 29)..close(), _paint(const Color(0xFFC7E9F2)));
    _line(canvas, Path()..moveTo(8, 12)..lineTo(67, 12), _mint, 2);
    _line(canvas, Path()..moveTo(8, 23)..lineTo(67, 23), _mint, 2);
    _box(canvas, const Rect.fromLTWH(-3, 42, 125, 7), _ink, 2);
    for (final x in [21.0, 97.0]) {
      canvas.drawCircle(Offset(x, 49), 12, _paint(_ink));
      canvas.drawCircle(Offset(x, 49), 5, _paint(Colors.white));
    }
    canvas.restore();
  }

  void _fish(Canvas canvas, Offset center) {
    canvas.drawOval(Rect.fromCenter(center: center, width: 25, height: 12), _paint(_green));
    canvas.drawPath(Path()
      ..moveTo(center.dx - 9, center.dy)
      ..lineTo(center.dx - 19, center.dy - 7)
      ..lineTo(center.dx - 19, center.dy + 7)..close(), _paint(_green));
    canvas.drawCircle(Offset(center.dx + 7, center.dy - 1), 1.5, _paint(Colors.white));
  }

  void _ponds(Canvas canvas) {
    _line(canvas, Path()
      ..moveTo(146, 89)..lineTo(187, 89)..lineTo(187, 168)
      ..lineTo(220, 168), const Color(0xFFB6CBBF), 22);
    _line(canvas, Path()..moveTo(146, 190)..lineTo(187, 190)
      ..lineTo(187, 168), const Color(0xFFB6CBBF), 22);
    for (var y = 102.0; y < 162; y += 17) {
      _line(canvas, Path()..moveTo(187, y)..lineTo(187, y + 7), Colors.white, 2);
    }
    for (final y in [42.0, 147.0]) {
      _box(canvas, Rect.fromLTWH(23, y, 128, 78), const Color(0xFFBBDDC0), 17);
      _box(canvas, Rect.fromLTWH(30, y + 7, 114, 64), const Color(0xFF8FCFC2), 12);
      for (var x = 42.0; x < 131; x += 26) {
        _line(canvas, Path()..moveTo(x, y + 54)
          ..quadraticBezierTo(x + 6, y + 48, x + 13, y + 54), const Color(0xFFDDF4EA), 2);
      }
    }
    _fish(canvas, const Offset(74, 73));
    _fish(canvas, const Offset(113, 91));
    _line(canvas, Path()..moveTo(77, 170)
      ..cubicTo(118, 164, 116, 201, 82, 193), _amber, 8);
    _line(canvas, Path()..moveTo(78, 170)..lineTo(66, 161)
      ..moveTo(78, 175)..lineTo(62, 175)
      ..moveTo(87, 191)..lineTo(82, 202), _amber, 2);
    canvas.drawCircle(const Offset(76, 170), 2, _paint(_ink));
    _truck(canvas, const Offset(215, 145), scale: 0.95);
    _box(canvas, const Rect.fromLTWH(211, 58, 126, 42), Colors.white);
    _text(canvas, _tr('కైకలూరు', 'Kaikaluru'), const Offset(223, 70));
    _text(canvas, _tr('ఆకివీడు', 'Akividu'), const Offset(34, 239));
    _text(canvas, _tr('భీమవరం', 'Bhimavaram'), const Offset(222, 239));
    canvas.drawCircle(const Offset(192, 243), 4, _paint(_green));
    _line(canvas, Path()..moveTo(115, 243)..lineTo(176, 243), _green, 2);
    _line(canvas, Path()..moveTo(172, 239)..lineTo(178, 243)..lineTo(172, 247), _green, 2);
  }

  void _cards(Canvas canvas) {
    _box(canvas, const Rect.fromLTWH(28, 44, 142, 186), const Color(0xFFCEEAD6), 18);
    _box(canvas, const Rect.fromLTWH(40, 33, 142, 186), Colors.white, 18);
    _box(canvas, const Rect.fromLTWH(40, 33, 142, 8), _green, 4);
    canvas.drawCircle(const Offset(73, 77), 18, _paint(_mint));
    _check(canvas, const Offset(89, 89));
    _text(canvas, _tr('డ్రైవర్ కార్డు', 'Driver card'), const Offset(52, 106), width: 122);
    _truck(canvas, const Offset(53, 143), scale: 0.56);
    _box(canvas, const Rect.fromLTWH(52, 183, 112, 24), const Color(0xFFE6F4EA), 8);
    _text(canvas, _tr('1.5 టన్నులు', '1.5 tons'), const Offset(64, 187), size: 11);
    _box(canvas, const Rect.fromLTWH(184, 65, 150, 176), const Color(0xFFCEEAD6), 18);
    _box(canvas, const Rect.fromLTWH(174, 53, 150, 176), Colors.white, 18);
    _box(canvas, const Rect.fromLTWH(174, 53, 150, 8), const Color(0xFF0E7490), 4);
    _text(canvas, _tr('నేరుగా పరిచయం', 'Meet your driver'), const Offset(188, 77), width: 123);
    _truck(canvas, const Offset(190, 118), scale: 0.85);
    _box(canvas, const Rect.fromLTWH(187, 185, 83, 28), const Color(0xFFFFF3D6), 9);
    _text(canvas, _tr('3 టన్నులు', '3 tons'), const Offset(197, 191), size: 11);
    _check(canvas, const Offset(299, 199));
    for (var x = 49.0; x < 325; x += 17) {
      canvas.drawCircle(Offset(x, 255), 2, _paint(_mint));
    }
  }

  void _person(Canvas canvas, Offset center, {required bool farmer}) {
    canvas.drawCircle(center, 45, _paint(Colors.white));
    canvas.drawCircle(Offset(center.dx, center.dy - 11), 17, _paint(const Color(0xFFE2B995)));
    _box(canvas, Rect.fromLTWH(center.dx - 24, center.dy + 8, 48, 29), farmer ? _green : const Color(0xFF0E7490), 16);
    if (farmer) {
      _box(canvas, Rect.fromLTWH(center.dx - 17, center.dy - 34, 34, 14), const Color(0xFFE7BC61), 9);
      _line(canvas, Path()..moveTo(center.dx - 25, center.dy - 20)
        ..lineTo(center.dx + 25, center.dy - 20), _amber, 5);
    } else {
      _box(canvas, Rect.fromLTWH(center.dx - 18, center.dy - 29, 39, 11), _green, 6);
    }
  }

  void _contact(Canvas canvas) {
    _line(canvas, Path()..moveTo(83, 112)
      ..cubicTo(119, 27, 241, 27, 278, 112), _mint, 3);
    _person(canvas, const Offset(78, 123), farmer: true);
    _person(canvas, const Offset(282, 123), farmer: false);
    _text(canvas, _tr('రైతు', 'Farmer'), const Offset(52, 176), width: 80);
    _text(canvas, _tr('డ్రైవర్', 'Driver'), const Offset(256, 176), width: 80);
    canvas.drawCircle(const Offset(180, 124), 31, _paint(_green));
    _line(canvas, Path()..moveTo(170, 111)
      ..cubicTo(165, 125, 179, 139, 192, 133)
      ..lineTo(187, 127)..lineTo(182, 129)
      ..lineTo(175, 122)..lineTo(177, 117)..close(), Colors.white, 3);
    _box(canvas, const Rect.fromLTWH(43, 216, 123, 34), Colors.white, 17);
    _box(canvas, const Rect.fromLTWH(184, 216, 135, 34), Colors.white, 17);
    _text(canvas, _tr('ఫోన్ చేయండి', 'Direct call'), const Offset(58, 225), size: 11);
    _text(canvas, _tr('వాట్సాప్', 'WhatsApp'), const Offset(225, 225), size: 11);
    _line(canvas, Path()..moveTo(201, 224)..lineTo(215, 224)
      ..lineTo(215, 236)..lineTo(207, 236)..lineTo(201, 241)..close(), _green, 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 360, size.height / 280);
    canvas.save();
    canvas.translate((size.width - 360 * scale) / 2, (size.height - 280 * scale) / 2);
    canvas.scale(scale);
    canvas.drawCircle(const Offset(330, 13), 62, _paint(const Color(0xFFD8EEDD)));
    canvas.drawCircle(const Offset(6, 271), 52, _paint(const Color(0xFFD8EEDD)));
    switch (step) {
      case 0: _ponds(canvas);
      case 1: _cards(canvas);
      case 2: _contact(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AquaIllustrationPainter oldDelegate) =>
      step != oldDelegate.step || language != oldDelegate.language;
}
