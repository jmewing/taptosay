import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The four connection values the tablet needs, as carried inside a
/// provisioning QR code.
class ScannedSetup {
  final String schoolId;
  final String studentId;
  final String authPassword;
  final String serverUrl;

  const ScannedSetup({
    required this.schoolId,
    required this.studentId,
    required this.authPassword,
    required this.serverUrl,
  });

  /// Parse the raw text of a scanned QR.
  ///
  /// The server emits an Android device-owner provisioning payload:
  ///
  ///   {"android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME": "...",
  ///    "android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE": {
  ///       "server_url": "...", "tablet_id": "...", "student_id": "...",
  ///       "school_tea_id": "...", "auth_password": "..." } }
  ///
  /// Student and teacher QRs share that shape — the only difference is that a
  /// teacher presents her T-code as `student_id`, which this parser does not
  /// care about.
  ///
  /// Also accepts a bare `{server_url: ...}` object, or a URL carrying the same
  /// fields as query parameters, so a setup printed by hand still works.
  ///
  /// Returns null when the text carries no usable settings; [error] explains
  /// why so the caller can show something better than "invalid QR".
  static ScannedSetup? tryParse(String raw, {String? Function(String)? onError}) {
    final text = raw.trim();
    if (text.isEmpty) {
      onError?.call('That QR code is empty.');
      return null;
    }

    Map<String, dynamic>? obj;

    // 1. JSON (the normal case).
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) obj = decoded;
      } catch (_) {
        // fall through to the URL / query-string attempts below
      }
    }

    // 2. Pull the extras bundle out; fall back to the object itself.
    Map<String, dynamic> extras = {};
    if (obj != null) {
      final bundle = obj['android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE'];
      if (bundle is Map) {
        extras = bundle.map((k, v) => MapEntry(k.toString(), v));
      } else {
        extras = obj;
      }
    } else {
      // 3. URL / query-string form: ?server_url=...&student_id=...
      try {
        final uri = Uri.parse(text);
        if (uri.queryParameters.isNotEmpty) {
          extras = Map<String, dynamic>.from(uri.queryParameters);
        }
      } catch (_) {
        // not a URL either
      }
    }

    String pick(List<String> keys) {
      for (final k in keys) {
        final v = extras[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return '';
    }

    final schoolId = pick(['school_tea_id', 'school_id', 'tea_id']);
    final studentId = pick(['student_id', 'tablet_id']);
    final auth = pick(['auth_password', 'password']);
    final url = pick(['server_url', 'server']);

    if (studentId.isEmpty && auth.isEmpty) {
      onError?.call(
        "That QR code doesn't contain TapToSay setup details.",
      );
      return null;
    }

    return ScannedSetup(
      schoolId: schoolId,
      studentId: studentId,
      authPassword: auth,
      serverUrl: url,
    );
  }
}

/// Full-screen QR scanner. Pops with a [ScannedSetup] when it reads a code the
/// app can use; pops with null if the user backs out.
///
/// Two ways in, because a parent may have the code printed OR already have it
/// as a screenshot on the phone:
///   * live camera preview
///   * "Choose a photo" — scans an existing image from the gallery
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  bool _handled = false; // guards against firing twice on one code
  bool _starting = true;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.start();
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _problem = 'Camera unavailable.\n\n$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Take the first usable barcode from a capture and close.
  void _consume(BarcodeCapture? capture) {
    if (_handled || capture == null) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;

      String? why;
      final setup = ScannedSetup.tryParse(raw, onError: (m) => why = m);
      if (setup != null) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop(setup);
        return;
      }
      if (mounted) setState(() => _problem = why);
      return; // one bad code at a time; let the user reposition
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    try {
      final capture = await _controller.analyzeImage(file.path);
      if (capture == null) {
        if (mounted) {
          setState(() => _problem = 'No QR code found in that photo.');
        }
        return;
      }
      _consume(capture);
    } catch (e) {
      if (mounted) setState(() => _problem = 'Could not read that photo.\n\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan setup QR'),
        backgroundColor: const Color(0xFF00838F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_problem == null)
                  MobileScanner(
                    controller: _controller,
                    onDetect: _consume,
                    errorBuilder: (context, error) => _CameraProblem(
                      text: 'Camera unavailable.\n\n${error.errorCode}',
                    ),
                  )
                else
                  _CameraProblem(text: _problem!),
                if (_starting)
                  const Center(child: CircularProgressIndicator()),
                // Simple framing guide so the parent knows where to aim.
                if (_problem == null)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Point the camera at the QR code from your school.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  label: const Text(
                    'Choose a photo instead',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  final String text;
  const _CameraProblem({required this.text});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
