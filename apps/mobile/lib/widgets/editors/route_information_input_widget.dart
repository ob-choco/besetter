import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

const int kRouteTitleMaxLength = 50;
const int kRouteDescriptionMaxLength = 500;
const int kRouteGradeScoreMax = 10000;

enum GradeType {
  yds('YDS', 'yds'),
  french('FRENCH', 'french'),
  vScale('V-SCALE', 'vScale'),
  fontScale('FONT SCALE', 'fontScale');

  final String displayName;
  final String value;
  const GradeType(this.displayName, this.value);
}

class RouteInformationInput extends StatefulWidget {
  final Function(GradeType) onGradeTypeChanged;
  final Function(String?) onGradeChanged;
  final Function(Color?) onGradeColorChanged;
  final Function(int?) onGradeScoreChanged;
  final Function(String?) onTitleChanged;
  final Function(String?) onDescriptionChanged;
  final String? gradeError;
  final GradeType? selectedGradeType;
  final String? selectedGrade;
  final Color? selectedGradeColor;
  final int? gradeScore;
  final String? title;
  final String? description;

  const RouteInformationInput({
    Key? key,
    required this.onGradeTypeChanged,
    required this.onGradeChanged,
    required this.onGradeColorChanged,
    required this.onGradeScoreChanged,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    this.gradeError,
    this.selectedGradeType,
    this.selectedGrade,
    this.selectedGradeColor,
    this.gradeScore,
    this.title,
    this.description,
  }) : super(key: key);

  @override
  State<RouteInformationInput> createState() => _RouteInformationInputState();
}

class _RouteInformationInputState extends State<RouteInformationInput> {
  final TextEditingController _scoreController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  final Map<GradeType, List<String>> gradesByType = {
    GradeType.yds: [
      '5.0',
      '5.1',
      '5.2',
      '5.3',
      '5.4',
      '5.5',
      '5.6',
      '5.7',
      '5.8',
      '5.9',
      '5.10a',
      '5.10b',
      '5.10c',
      '5.10d',
      '5.11a',
      '5.11b',
      '5.11c',
      '5.11d',
      '5.12a',
      '5.12b',
      '5.12c',
      '5.12d',
      '5.13a',
      '5.13b',
      '5.13c',
      '5.13d',
      '5.14a',
      '5.14b',
      '5.14c',
      '5.14d',
      '5.15a',
      '5.15b',
      '5.15c',
      '5.15d',
    ],
    GradeType.french: [
      '3',
      '3+',
      '4',
      '4+',
      '5',
      '5+',
      '6a',
      '6a+',
      '6b',
      '6b+',
      '6c',
      '6c+',
      '7a',
      '7a+',
      '7b',
      '7b+',
      '7c',
      '7c+',
      '8a',
      '8a+',
      '8b',
      '8b+',
      '8c',
      '8c+',
      '9a',
      '9a+',
      '9b',
      '9b+',
      '9c',
    ],
    GradeType.vScale: [
      'V0',
      'V1',
      'V2',
      'V3',
      'V4',
      'V5',
      'V6',
      'V7',
      'V8',
      'V9',
      'V10',
      'V11',
      'V12',
      'V13',
      'V14',
      'V15',
      'V16',
      'V17',
    ],
    GradeType.fontScale: [
      '3',
      '4',
      '4+',
      '5',
      '5+',
      '6a',
      '6a+',
      '6b',
      '6b+',
      '6c',
      '6c+',
      '7a',
      '7a+',
      '7b',
      '7b+',
      '7c',
      '7c+',
      '8a',
      '8a+',
      '8b',
      '8b+',
      '8c',
      '8c+',
      '9a',
    ],
  };

  final List<Color> routeColors = [
    Colors.white,
    const Color.fromARGB(255, 255, 255, 0),
    const Color.fromARGB(255, 0, 255, 0),
    const Color.fromARGB(255, 0, 0, 255),
    const Color.fromARGB(255, 255, 0, 0),
    Colors.black,
    Colors.grey,
    Colors.brown,
    const Color.fromARGB(255, 255, 0, 255),
  ];

  @override
  void initState() {
    super.initState();
    _scoreController.text = widget.gradeScore?.toString() ?? '';
    _titleController.text = widget.title ?? '';
    _descriptionController.text = widget.description ?? '';
  }

  @override
  void didUpdateWidget(RouteInformationInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.title != oldWidget.title && (widget.title ?? '') != _titleController.text) {
      _titleController.text = widget.title ?? '';
    }
    if (widget.description != oldWidget.description &&
        (widget.description ?? '') != _descriptionController.text) {
      _descriptionController.text = widget.description ?? '';
    }
    if (widget.gradeScore != oldWidget.gradeScore &&
        (widget.gradeScore?.toString() ?? '') != _scoreController.text) {
      _scoreController.text = widget.gradeScore?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _showRouteInfoModal() async {
    final TextEditingController tempTitleController = TextEditingController(text: _titleController.text);
    final TextEditingController tempDescriptionController = TextEditingController(text: _descriptionController.text);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
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
                  AppLocalizations.of(context)!.titleDescription,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: tempTitleController,
                  maxLength: kRouteTitleMaxLength,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.title,
                    hintText: AppLocalizations.of(context)!.enterTitle,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: tempDescriptionController,
                  maxLines: 3,
                  maxLength: kRouteDescriptionMaxLength,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.description,
                    hintText: AppLocalizations.of(context)!.enterDescription,
                  ),
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
                        _titleController.text = tempTitleController.text;
                        _descriptionController.text = tempDescriptionController.text;
                        widget.onTitleChanged(tempTitleController.text.isEmpty ? null : tempTitleController.text);
                        widget.onDescriptionChanged(
                            tempDescriptionController.text.isEmpty ? null : tempDescriptionController.text);
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
  }

  String _getRouteInfoSubtitle() {
    if (_titleController.text.isEmpty && _descriptionController.text.isEmpty) {
      return AppLocalizations.of(context)!.selectAndEnter;
    }

    if (_titleController.text.isNotEmpty && _descriptionController.text.isNotEmpty) {
      final description = _descriptionController.text.length > 20
          ? '${_descriptionController.text.substring(0, 20)}...'
          : _descriptionController.text;
      return '${_titleController.text} / $description';
    }

    return _titleController.text.isNotEmpty ? _titleController.text : _descriptionController.text;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.routeInfo,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: widget.gradeError != null ? Colors.red : null,
            ),
          ),
          if (widget.selectedGrade == null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                AppLocalizations.of(context)!.selectGrade,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<GradeType>(
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.gradeType,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down),
                  value: widget.selectedGradeType,
                  items: GradeType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      widget.onGradeTypeChanged(value);
                      widget.onGradeChanged(null);
                    }
                  },
                  hint: Text(AppLocalizations.of(context)!.selectGradeType),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.grade,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red),
                    ),
                    errorStyle: TextStyle(height: 0),
                  ),
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down),
                  value: widget.selectedGrade,
                  items: widget.selectedGradeType != null
                      ? gradesByType[widget.selectedGradeType]!.map((grade) {
                          return DropdownMenuItem(
                            value: grade,
                            child: Text(grade),
                          );
                        }).toList()
                      : [],
                  onChanged: widget.selectedGradeType != null
                      ? (value) {
                          widget.onGradeChanged(value);
                        }
                      : null,
                  hint: Text(widget.selectedGradeType == null
                      ? AppLocalizations.of(context)!.selectGradeTypeFirst
                      : AppLocalizations.of(context)!.selectGradeInstruction),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(AppLocalizations.of(context)!.colorOptional, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...routeColors.map((color) {
                return InkWell(
                  onTap: () {
                    widget.onGradeColorChanged(color == widget.selectedGradeColor ? null : color);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: color == Colors.white ? Colors.grey : Colors.transparent,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: color == widget.selectedGradeColor
                        ? Icon(
                            Icons.check,
                            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                          )
                        : null,
                  ),
                );
              }),
            ],
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: _scoreController,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.scoreOptional,
              hintText: AppLocalizations.of(context)!.enterScore,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed == null) {
                widget.onGradeScoreChanged(null);
                return;
              }
              final clamped = parsed.clamp(0, kRouteGradeScoreMax);
              if (clamped != parsed) {
                _scoreController.text = clamped.toString();
                _scoreController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _scoreController.text.length),
                );
              }
              widget.onGradeScoreChanged(clamped);
            },
          ),
          Divider(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(AppLocalizations.of(context)!.titleDescription),
            subtitle: Text(_getRouteInfoSubtitle()),
            trailing: Icon(Icons.chevron_right),
            onTap: _showRouteInfoModal,
          ),
        ],
      ),
    );
  }
}
