// live_order_ui.dart
// Palette, helper-widgets dùng chung trong toàn bộ flow chốt đơn live

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// ─── Palette ──────────────────────────────────────────────────
const kGreen = Color(0xFF34C759);
const kBlue = Color(0xFF007AFF);
const kOrange = Color(0xFFFF9F0A);
const kRed = Color(0xFFFF3B30);
const kBg = Color(0xFFF2F2F7);

// ─── Format tiền ──────────────────────────────────────────────
String fmtMoney(double v) => v.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

// ─── Section label ────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String label;
  const SectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6C6C70),
                letterSpacing: 0.2)),
      );
}

// ─── White card container ─────────────────────────────────────
class WhiteCard extends StatelessWidget {
  final Widget child;
  const WhiteCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: child,
      );
}

// ─── Horizontal divider in card ───────────────────────────────
class HDivider extends StatelessWidget {
  const HDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, color: Colors.grey.shade100),
      );
}

// ─── Field row inside card ────────────────────────────────────
class FieldRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const FieldRow({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(icon, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: label,
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      );
}

// ─── Gradient action button ───────────────────────────────────
class GradientButton extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final IconData icon;
  final VoidCallback? onTap;

  const GradientButton({
    super.key,
    required this.label,
    required this.colors,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight),
              borderRadius: BorderRadius.circular(14),
              boxShadow: onTap != null
                  ? [
                      BoxShadow(
                          color: colors.last.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ]
                  : [],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

// ─── Info / warning banner ────────────────────────────────────
class InfoBox extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const InfoBox(
      {super.key, required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25))),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600))),
        ]),
      );
}

// ─── Bottom-sheet handle ──────────────────────────────────────
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
      );
}

// ─── Sheet close button ───────────────────────────────────────
class SheetCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const SheetCloseButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: Colors.grey.shade200, shape: BoxShape.circle),
          child:
              const Icon(CupertinoIcons.xmark, size: 14, color: Colors.black54),
        ),
      );
}
