import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// Per-device alert settings: pop-up on/off, sound on/off and a sound for
/// each kind of message. Tapping a sound plays it.
Future<void> showNotificationSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => const _NotificationSettingsSheet(),
  );
}

class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  final _svc = NotificationService.instance;

  Future<void> _pickSound(AlertKind kind, String code) async {
    await _svc.setSoundOf(kind, code);
    if (mounted) setState(() {});
    _svc.playSound(code);
  }

  Future<void> _tryAlert() async {
    if (_svc.soundEnabled) _svc.playSound(_svc.soundOf(AlertKind.normal));
    if (_svc.popupEnabled) {
      await _svc.showPopup(
        id: 1,
        title: 'ตัวอย่างการแจ้งเตือน',
        body: 'ข้อความใหม่จะเด้งแบบนี้ พร้อมเสียงที่เลือกไว้',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'เสียงและการแจ้งเตือน',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'ตั้งค่าเฉพาะเครื่องนี้ แตะชื่อเสียงเพื่อฟังตัวอย่าง',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.slateMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('แสดงป๊อปอัปเมื่อมีข้อความใหม่'),
                value: _svc.popupEnabled,
                onChanged: (v) async {
                  await _svc.setPopupEnabled(v);
                  if (mounted) setState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('เล่นเสียงแจ้งเตือน'),
                value: _svc.soundEnabled,
                onChanged: (v) async {
                  await _svc.setSoundEnabled(v);
                  if (mounted) setState(() {});
                },
              ),
              for (final kind in AlertKind.values) ...[
                const SizedBox(height: 12),
                Text(
                  kind.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in NotificationService.sounds)
                      ChoiceChip(
                        label: Text(s.name),
                        avatar: Icon(
                          s.code == NotificationService.noSound
                              ? Icons.volume_off_rounded
                              : Icons.music_note_rounded,
                          size: 16,
                        ),
                        selected: _svc.soundOf(kind) == s.code,
                        onSelected: _svc.soundEnabled
                            ? (_) => _pickSound(kind, s.code)
                            : null,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _tryAlert,
                icon: const Icon(Icons.notifications_active_rounded, size: 18),
                label: const Text('ลองแจ้งเตือน'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
