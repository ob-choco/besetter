import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/user_provider.dart';

enum _HintState { idle, checking, available, error }

class ProfileIdEditDialog extends ConsumerStatefulWidget {
  final String currentProfileId;

  const ProfileIdEditDialog({super.key, required this.currentProfileId});

  @override
  ConsumerState<ProfileIdEditDialog> createState() =>
      _ProfileIdEditDialogState();

  static Future<bool> show(
    BuildContext context, {
    required String currentProfileId,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          ProfileIdEditDialog(currentProfileId: currentProfileId),
    );
    return result ?? false;
  }
}

class _ProfileIdEditDialogState extends ConsumerState<ProfileIdEditDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  _HintState _hintState = _HintState.idle;
  String? _reason;
  bool _submitting = false;
  String _lastCheckedValue = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentProfileId);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final value = _controller.text;
    _debounce?.cancel();

    if (value.isEmpty || value == widget.currentProfileId) {
      setState(() {
        _hintState = _HintState.idle;
        _reason = null;
      });
      return;
    }

    setState(() {
      _hintState = _HintState.checking;
      _reason = null;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      await _runAvailabilityCheck(value);
    });
  }

  Future<void> _runAvailabilityCheck(String value) async {
    try {
      final result = await ref
          .read(userProfileProvider.notifier)
          .checkProfileIdAvailability(value);
      if (!mounted || _controller.text != value) return;
      _lastCheckedValue = value;
      setState(() {
        if (result.available) {
          _hintState = _HintState.available;
          _reason = null;
        } else {
          _hintState = _HintState.error;
          _reason = result.reason;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hintState = _HintState.error;
        _reason = 'UNKNOWN';
      });
    }
  }

  String? _reasonMessage(BuildContext context, String? reason) {
    if (reason == null) return null;
    final l10n = AppLocalizations.of(context)!;
    switch (reason) {
      case 'PROFILE_ID_TOO_SHORT':
        return l10n.profileIdErrorTooShort;
      case 'PROFILE_ID_TOO_LONG':
        return l10n.profileIdErrorTooLong;
      case 'PROFILE_ID_INVALID_CHARS':
        return l10n.profileIdErrorInvalidChars;
      case 'PROFILE_ID_INVALID_START_END':
        return l10n.profileIdErrorInvalidStartEnd;
      case 'PROFILE_ID_CONSECUTIVE_SPECIAL':
        return l10n.profileIdErrorConsecutiveSpecial;
      case 'PROFILE_ID_RESERVED':
        return l10n.profileIdErrorReserved;
      case 'PROFILE_ID_TAKEN':
        return l10n.profileIdErrorTaken;
      default:
        return null;
    }
  }

  Widget _buildHint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_hintState) {
      case _HintState.idle:
        return const SizedBox(height: 20);
      case _HintState.checking:
        return Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Text(l10n.profileIdHintChecking),
          ],
        );
      case _HintState.available:
        return Row(
          children: [
            const Icon(Icons.check, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              l10n.profileIdHintAvailable,
              style: const TextStyle(color: Colors.green),
            ),
          ],
        );
      case _HintState.error:
        final msg = _reasonMessage(context, _reason) ?? '';
        return Row(
          children: [
            const Icon(Icons.close, size: 16, color: Colors.red),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
    }
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_hintState != _HintState.available) return false;
    if (_controller.text != _lastCheckedValue) return false;
    return true;
  }

  Future<void> _onSubmit() async {
    final value = _controller.text;
    setState(() => _submitting = true);
    try {
      await ref.read(userProfileProvider.notifier).updateProfileId(value);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileIdUpdated)),
      );
      Navigator.of(context).pop(true);
    } on ProfileIdUpdateError catch (e) {
      if (!mounted) return;
      setState(() {
        _hintState = _HintState.error;
        _reason = e.code;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hintState = _HintState.error;
        _reason = 'UNKNOWN';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.editProfileIdTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 30,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9._]')),
            ],
            decoration: InputDecoration(
              prefixText: '@',
              labelText: l10n.profileIdLabel,
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          _buildHint(context),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        ElevatedButton(
          onPressed: _canSubmit ? _onSubmit : null,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
