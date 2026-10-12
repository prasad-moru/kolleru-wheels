import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shared avatar display and compressed gallery picker for driver journeys.
class DriverAvatarPicker extends StatefulWidget {
  const DriverAvatarPicker({
    super.key,
    required this.name,
    this.imageUrl,
    this.initialBytes,
    this.size = 88,
    this.editable = true,
    this.onPhotoSelected,
  });

  final String name;
  final String? imageUrl;
  final Uint8List? initialBytes;
  final double size;
  final bool editable;
  final ValueChanged<Uint8List>? onPhotoSelected;

  @override
  State<DriverAvatarPicker> createState() => _DriverAvatarPickerState();
}

class _DriverAvatarPickerState extends State<DriverAvatarPicker> {
  final _picker = ImagePicker();
  bool _picking = false;

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) widget.onPhotoSelected?.call(bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ఫోటో తెరవలేకపోయాం / Could not open photo'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String get _initials {
    final parts = widget.name
        .split('/')
        .first
        .trim()
        .split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'KW';
    return parts.take(2).map((part) => part.characters.first).join();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFE0F0E7), Color(0xFFF2F7F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        _initials,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: const Color(0xFF236449),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    final image = widget.initialBytes != null
        ? Image.memory(
            widget.initialBytes!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          )
        : widget.imageUrl == null || widget.imageUrl!.isEmpty
        ? fallback
        : Image.network(
            widget.imageUrl!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );

    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (_picking)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
    if (!widget.editable) return avatar;
    return Semantics(
      button: true,
      label: 'Driver photo. Tap to choose a photo',
      child: GestureDetector(
        key: const ValueKey('driver-avatar-picker'),
        onTap: _picking ? null : _pickPhoto,
        child: SizedBox(
          width: widget.size + 8,
          height: widget.size + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 0, top: 0, child: avatar),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF087C55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
