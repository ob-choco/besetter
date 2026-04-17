import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../models/place_data.dart';
import '../animations/shake_animation_widget.dart';
import '../place_pending_badge.dart';
import 'place_selection_sheet.dart';

class SprayWallInformationInput extends StatefulWidget {
  final PlaceData? selectedPlace;
  final Function(PlaceData?) onPlaceChanged;
  final double? exifLatitude;
  final double? exifLongitude;
  final TextEditingController wallNameController;
  final Function(String) onWallNameChanged;
  final Function(DateTime?)? onWallExpirationDateChanged;
  final String? wallNameError;
  final DateTime? wallExpirationDate;
  final bool isGymInfoInvalid;
  final bool isDateInvalid;

  const SprayWallInformationInput({
    Key? key,
    required this.selectedPlace,
    required this.onPlaceChanged,
    this.exifLatitude,
    this.exifLongitude,
    required this.wallNameController,
    required this.onWallNameChanged,
    this.onWallExpirationDateChanged,
    this.wallNameError,
    this.wallExpirationDate,
    this.isGymInfoInvalid = false,
    this.isDateInvalid = false,
  }) : super(key: key);

  @override
  State<SprayWallInformationInput> createState() => _SprayWallInformationInputState();
}

class _SprayWallInformationInputState extends State<SprayWallInformationInput> {
  Future<void> _showPlaceSelection() async {
    final result = await PlaceSelectionSheet.show(
      context,
      latitude: widget.exifLatitude,
      longitude: widget.exifLongitude,
      currentPlace: widget.selectedPlace,
    );
    if (result == null) return;
    if (result.cleared) {
      widget.onPlaceChanged(null);
    } else if (result.place != null) {
      widget.onPlaceChanged(result.place);
    }
  }

  Future<void> _showWallNameModal() async {
    final TextEditingController tempWallNameController = TextEditingController(text: widget.wallNameController.text);
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
                      AppLocalizations.of(context)!.wallLocation,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
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
                            if (tempWallNameController.text.trim().isEmpty) {
                              setModalState(() => tempWallNameError = AppLocalizations.of(context)!.enterWallLocation);
                              return;
                            }

                            widget.wallNameController.text = tempWallNameController.text.trim();
                            widget.onWallNameChanged(widget.wallNameController.text);
                            Navigator.pop(context);
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
    final bool hasPlace = widget.selectedPlace != null;
    final bool hasWallName = widget.wallNameController.text.isNotEmpty;
    final bool hasDateInfo = widget.wallExpirationDate != null;

    return Column(
      children: [
        ShakeAnimationWidget(
          shakeTrigger: widget.isGymInfoInvalid,
          child: Column(
            children: [
              ListTile(
                title: Text(AppLocalizations.of(context)!.climbingGymInfo),
                subtitle: hasPlace
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '\u2713 ${widget.selectedPlace!.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.selectedPlace!.isPending) ...[
                            const SizedBox(width: 6),
                            const PlacePendingBadge(),
                          ],
                        ],
                      )
                    : Text(
                        AppLocalizations.of(context)!.selectAndEnter,
                        style: TextStyle(
                          color: widget.isGymInfoInvalid ? Colors.red : null,
                        ),
                      ),
                trailing: Icon(Icons.chevron_right),
                onTap: _showPlaceSelection,
              ),
              ListTile(
                title: Text(AppLocalizations.of(context)!.wallLocation),
                subtitle: Text(
                  hasWallName
                      ? widget.wallNameController.text
                      : AppLocalizations.of(context)!.selectAndEnter,
                  style: TextStyle(
                    color: widget.isGymInfoInvalid && !hasWallName ? Colors.red : null,
                  ),
                ),
                trailing: Icon(Icons.chevron_right),
                onTap: _showWallNameModal,
              ),
            ],
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
      ],
    );
  }
}
