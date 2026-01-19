import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../animations/shake_animation_widget.dart';

// enum VisibilityLevel {
//   private,
//   public,
//   friendsOnly,
//   linkOnly,
// }

class SprayWallInformationInput extends StatefulWidget {
  final TextEditingController gymNameController;
  final TextEditingController wallNameController;
  final Function(String) onGymNameChanged;
  final Function(String) onWallNameChanged;
  final Function(DateTime?)? onWallExpirationDateChanged;
  // final Function(VisibilityLevel)? onVisibilityLevelChanged;
  final String? gymNameError;
  final String? wallNameError;
  final DateTime? wallExpirationDate;
  // final VisibilityLevel visibilityLevel;
  final bool isGymInfoInvalid;
  final bool isDateInvalid;

  const SprayWallInformationInput({
    Key? key,
    required this.gymNameController,
    required this.wallNameController,
    required this.onGymNameChanged,
    required this.onWallNameChanged,
    this.onWallExpirationDateChanged,
    // this.onVisibilityLevelChanged,
    this.gymNameError,
    this.wallNameError,
    this.wallExpirationDate,
    // this.visibilityLevel = VisibilityLevel.private,
    this.isGymInfoInvalid = false,
    this.isDateInvalid = false,
  }) : super(key: key);

  @override
  State<SprayWallInformationInput> createState() => _SprayWallInformationInputState();
}

class _SprayWallInformationInputState extends State<SprayWallInformationInput> {
  Future<void> _showGymInfoModal() async {
    final TextEditingController tempGymNameController = TextEditingController(text: widget.gymNameController.text);
    final TextEditingController tempWallNameController = TextEditingController(text: widget.wallNameController.text);
    String? tempGymNameError;
    String? tempWallNameError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.climbingGymInfo,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: tempGymNameController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.gymName,
                        hintText: AppLocalizations.of(context)!.enterGymName,
                        errorText: tempGymNameError,
                      ),
                      onChanged: (_) => setModalState(() => tempGymNameError = null),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: tempWallNameController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.wallLocation,
                        hintText: AppLocalizations.of(context)!.enterWallLocation,
                        errorText: tempWallNameError,
                      ),
                      onChanged: (_) => setModalState(() => tempWallNameError = null),
                    ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(AppLocalizations.of(context)!.cancel),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            bool modalIsValid = true;
                            if (tempGymNameController.text.trim().isEmpty) {
                              setModalState(() => tempGymNameError = AppLocalizations.of(context)!.enterGymName);
                              modalIsValid = false;
                            }
                            if (tempWallNameController.text.trim().isEmpty) {
                              setModalState(() => tempWallNameError = AppLocalizations.of(context)!.enterWallLocation);
                              modalIsValid = false;
                            }

                            if (modalIsValid) {
                              widget.gymNameController.text = tempGymNameController.text.trim();
                              widget.wallNameController.text = tempWallNameController.text.trim();
                              widget.onGymNameChanged(widget.gymNameController.text);
                              widget.onWallNameChanged(widget.wallNameController.text);
                              Navigator.pop(context);
                            }
                          },
                          child: Text(AppLocalizations.of(context)!.confirm),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = widget.wallExpirationDate ?? now;
    final DateTime firstDate = DateTime.now().subtract(Duration(days: 365 * 10));

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(Duration(days: 365 * 10)),
      helpText: AppLocalizations.of(context)!.selectWallExpiryDate,
      cancelText: AppLocalizations.of(context)!.cancel,
      confirmText: AppLocalizations.of(context)!.select,
      locale: const Locale('ko', 'KR'),
    );

    if (picked != null && widget.onWallExpirationDateChanged != null) {
      widget.onWallExpirationDateChanged!(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasGymInfo = widget.gymNameController.text.isNotEmpty && widget.wallNameController.text.isNotEmpty;
    final bool hasDateInfo = widget.wallExpirationDate != null;

    return Column(
      children: [
        ShakeAnimationWidget(
          shakeTrigger: widget.isGymInfoInvalid,
          child: ListTile(
            title: Text(AppLocalizations.of(context)!.climbingGymInfo),
            subtitle: Text(
              hasGymInfo
                  ? '${widget.gymNameController.text} - ${widget.wallNameController.text}'
                  : AppLocalizations.of(context)!.selectAndEnter,
              style: TextStyle(
                color: widget.isGymInfoInvalid ? Colors.red : null,
              ),
            ),
            trailing: Icon(Icons.chevron_right),
            onTap: _showGymInfoModal,
          ),
        ),
        Divider(height: 1),
        ShakeAnimationWidget(
          shakeTrigger: widget.isDateInvalid,
          child: ListTile(
            title: Text(AppLocalizations.of(context)!.wallExpirationDate),
            subtitle: Text(
              hasDateInfo
                  ? DateFormat.yMMMMd(AppLocalizations.of(context)!.localeName).format(widget.wallExpirationDate!)
                  : AppLocalizations.of(context)!.selectAndEnter,
              style: TextStyle(
                color: widget.isDateInvalid ? Colors.red : null,
              ),
            ),
            trailing: hasDateInfo
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () {
                          if (widget.onWallExpirationDateChanged != null) {
                            widget.onWallExpirationDateChanged!(null);
                          }
                        },
                      ),
                      Icon(Icons.chevron_right),
                    ],
                  )
                : Icon(Icons.chevron_right),
            onTap: () => _selectDate(context),
          ),
        ),
        // Divider(height: 1),
        // SwitchListTile(
        //   title: Text('전체 공개'),
        //   value: widget.visibilityLevel == VisibilityLevel.public,
        //   onChanged: (bool value) {
        //     if (widget.onVisibilityLevelChanged != null) {
        //       widget.onVisibilityLevelChanged!(value ? VisibilityLevel.public : VisibilityLevel.private);
        //     }
        //   },
        // ),
      ],
    );
  }
}
