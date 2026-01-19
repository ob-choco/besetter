import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;
import 'endurance_route_editor.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class EnduranceHoldEditMenu extends StatefulWidget {
  final VoidCallback onReplace;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final List<int> orders;
  final Function(int) onOrderSelected;
  final int? initialSelectedOrder;
  final ui.Image? croppedImage;
  final HoldEditMode editMode;
  final VoidCallback onCancelHoldAdd;

  const EnduranceHoldEditMenu({
    Key? key,
    required this.onReplace,
    required this.onAdd,
    required this.onDelete,
    required this.orders,
    required this.onOrderSelected,
    required this.initialSelectedOrder,
    required this.editMode,
    required this.onCancelHoldAdd,
    this.croppedImage,
  }) : super(key: key);

  @override
  State<EnduranceHoldEditMenu> createState() => _EnduranceHoldEditMenuState();
}

class _EnduranceHoldEditMenuState extends State<EnduranceHoldEditMenu> {
  int? selectedOrder;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeSelectedOrder();
  }

  @override
  void didUpdateWidget(EnduranceHoldEditMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orders != widget.orders || oldWidget.initialSelectedOrder != widget.initialSelectedOrder) {
      _initializeSelectedOrder();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeSelectedOrder() {
    if (widget.orders.isNotEmpty) {
      if (widget.initialSelectedOrder != null && widget.orders.contains(widget.initialSelectedOrder)) {
        selectedOrder = widget.initialSelectedOrder;

        if (widget.orders.length > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final selectedIndex = widget.orders.indexOf(widget.initialSelectedOrder!);
            if (selectedIndex != -1) {
              final itemWidth = 30 + 8.0; // 아이템 너비 + 간격
              double scrollPosition;

              // 마지막 아이템인 경우
              if (selectedIndex == widget.orders.length - 1) {
                scrollPosition = _scrollController.position.maxScrollExtent;
              } else {
                scrollPosition = selectedIndex * itemWidth;
              }

              _scrollController.animateTo(
                scrollPosition,
                duration: Duration(milliseconds: 100),
                curve: Curves.linear,
              );
            }
          });
        }
      } else {
        selectedOrder = widget.orders.first;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onOrderSelected(selectedOrder!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Row(
              children: [
                if (widget.editMode == HoldEditMode.replace || widget.editMode == HoldEditMode.add)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.editMode == HoldEditMode.replace
                              ? AppLocalizations.of(context)!.selectHoldsToReplaceOnImage
                              : AppLocalizations.of(context)!.selectHoldsToAddOnImage,
                          style: TextStyle(fontSize: 16),
                        ),
                        ElevatedButton(
                          onPressed: widget.onCancelHoldAdd,
                          child: Text(AppLocalizations.of(context)!.cancel),
                        ),
                      ],
                    ),
                  ),
                if (!(widget.editMode == HoldEditMode.replace || widget.editMode == HoldEditMode.add))
                  Container(
                    width: 48,
                    height: 48,
                    margin: EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: widget.editMode == HoldEditMode.edit ? Colors.grey : Colors.grey.withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: widget.editMode == HoldEditMode.edit && widget.croppedImage != null
                        ? RawImage(
                            image: widget.croppedImage,
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                if (widget.editMode == HoldEditMode.edit)
                  IconButton(
                    onPressed: widget.onReplace,
                    icon: SvgPicture.asset(
                      'assets/icons/replace_button.svg',
                      width: 48,
                      height: 48,
                      colorFilter: ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    iconSize: 48,
                    tooltip: AppLocalizations.of(context)!.replace,
                  ),
                if (widget.editMode == HoldEditMode.edit)
                  IconButton(
                    onPressed: widget.onAdd,
                    icon: SvgPicture.asset(
                      'assets/icons/add_button.svg',
                      width: 48,
                      height: 48,
                      colorFilter: ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    iconSize: 48,
                    tooltip: AppLocalizations.of(context)!.add,
                  ),
                if (widget.editMode == HoldEditMode.edit)
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: SvgPicture.asset(
                      'assets/icons/delete_button.svg',
                      width: 48,
                      height: 48,
                      colorFilter: ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    iconSize: 48,
                    tooltip: AppLocalizations.of(context)!.delete,
                  ),
              ],
            ),
            if (widget.orders.length > 1)
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 32,
                    child: ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.orders.length,
                      separatorBuilder: (context, index) => SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final order = widget.orders[index];
                        final isSelected = order == selectedOrder;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedOrder = order;
                                });
                                widget.onOrderSelected(order);
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.yellow : Colors.red,
                                    width: isSelected ? 3 : 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected ? Colors.yellow.withOpacity(0.3) : Colors.red.withOpacity(0.2),
                                      spreadRadius: 2,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    order.toString(),
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                bottom: 20,
                                left: 15,
                                child: SvgPicture.asset(
                                  'assets/icons/check.svg',
                                  width: 16,
                                  height: 16,
                                  colorFilter: ColorFilter.mode(
                                    Color(0xFF007AFF),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
