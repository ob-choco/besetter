import 'dart:typed_data' as typed_data;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ImagePickerPage extends StatefulWidget {
  final List<File> initialSelectedImages;
  final bool allowMultiple;

  ImagePickerPage({
    required this.initialSelectedImages,
    this.allowMultiple = true,
  });

  @override
  _ImagePickerPageState createState() => _ImagePickerPageState();
}

class _ImagePickerPageState extends State<ImagePickerPage> {
  late List<File> selectedImages;
  Set<String> selectedAssetIds = {};
  List<AssetEntity> allImages = [];
  Map<String, File> imageCache = {};
  Map<String, ValueNotifier<bool>> _selectedStatusNotifiers = {};
  Map<String, Future<typed_data.Uint8List?>> _thumbnailFutures = {};
  bool isFullAccess = false;
  bool isLimitedAccess = false;
  bool isNoAccess = false;
  int currentPage = 0;
  int itemsPerPage = 30;
  String? _currentSingleSelectedAssetId;

  @override
  void initState() {
    super.initState();
    selectedImages = List.from(widget.initialSelectedImages);
    checkPermissionAndLoadImages();
  }

  Future<void> checkPermissionAndLoadImages() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth) {
      setState(() {
        isFullAccess = true;
        isLimitedAccess = false;
        isNoAccess = false;
      });
      await loadAllImages();
    } else if (ps.hasAccess) {
      setState(() {
        isFullAccess = false;
        isLimitedAccess = true;
        isNoAccess = false;
      });
      await loadLimitedAccessImages();
    } else {
      setState(() {
        isFullAccess = false;
        isLimitedAccess = false;
        isNoAccess = true;
      });
      if (allImages.isNotEmpty) {
        setState(() {
          allImages.clear();
          _selectedStatusNotifiers.clear();
          _thumbnailFutures.clear();
          selectedAssetIds.clear();
        });
      }
    }
  }

  Future<void> loadAllImages() async {
    currentPage = 0;
    allImages.clear();
    
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(onlyAll: true);
    if (albums.isNotEmpty) {
      List<AssetEntity> photos = await albums[0].getAssetListPaged(page: currentPage, size: itemsPerPage);
      setState(() {
        allImages.addAll(photos);
        _updateNotifiersAndFutures(photos);
        currentPage++;
      });
      await _syncInitialSelectionsWithAssets();
    } else {
      setState(() {});
    }
  }

  Future<void> loadLimitedAccessImages() async {
    currentPage = 0;
    allImages.clear();

    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );
    
    List<AssetEntity> accessibleAssets = [];
    for (var album in albums) {
      int totalAssetsInAlbum = await album.assetCountAsync;
      if (totalAssetsInAlbum > 0) {
        List<AssetEntity> albumPhotos = await album.getAssetListRange(start: 0, end: totalAssetsInAlbum);
        accessibleAssets.addAll(albumPhotos);
      }
    }

    final uniqueIds = <String>{};
    final uniqueAssets = accessibleAssets.where((asset) => uniqueIds.add(asset.id)).toList();

    setState(() {
      allImages = uniqueAssets;
      _updateNotifiersAndFutures(allImages, clearExisting: true);
    });
    await _syncInitialSelectionsWithAssets();
  }

  void _updateNotifiersAndFutures(List<AssetEntity> assets, {bool clearExisting = false}) {
    final currentAssetIdsInAssets = assets.map((a) => a.id).toSet();
    bool selectionStateChanged = false;

    int originalSelectedCount = selectedAssetIds.length;
    selectedAssetIds.removeWhere((id) => !currentAssetIdsInAssets.contains(id));
    if (selectedAssetIds.length != originalSelectedCount) {
      selectionStateChanged = true;
    }

    if (!widget.allowMultiple && _currentSingleSelectedAssetId != null && !selectedAssetIds.contains(_currentSingleSelectedAssetId)) {
      _currentSingleSelectedAssetId = null;
      selectionStateChanged = true; 
    }

    for (var asset in assets) {
      _selectedStatusNotifiers.putIfAbsent(asset.id, () => ValueNotifier(selectedAssetIds.contains(asset.id)));
      _selectedStatusNotifiers[asset.id]!.value = selectedAssetIds.contains(asset.id);
      _thumbnailFutures.putIfAbsent(asset.id, () => asset.thumbnailDataWithSize(const ThumbnailSize(200, 200), quality: 85));
    }

    _selectedStatusNotifiers.removeWhere((id, notifier) => !currentAssetIdsInAssets.contains(id));
    _thumbnailFutures.removeWhere((id, _) => !currentAssetIdsInAssets.contains(id));
  }

  Future<void> _syncInitialSelectionsWithAssets() async {
    if (widget.initialSelectedImages.isEmpty && selectedAssetIds.isEmpty) return;

    bool selectionChanged = false;

    if (widget.initialSelectedImages.isNotEmpty) {
        for (File initialFile in widget.initialSelectedImages) {
            AssetEntity? matchedAsset;
            for (AssetEntity asset in allImages) {
                File? assetFile = imageCache[asset.id];
                if (assetFile == null) {
                }
                assetFile = imageCache[asset.id] ?? await asset.file;
                if (assetFile != null) {
                    imageCache[asset.id] = assetFile;
                    if (assetFile.path == initialFile.path) {
                        matchedAsset = asset;
                        break;
                    }
                }
            }

            if (matchedAsset != null) {
                if (!selectedAssetIds.contains(matchedAsset.id)) {
                    selectedAssetIds.add(matchedAsset.id);
                    _selectedStatusNotifiers[matchedAsset.id]?.value = true;
                    if (!selectedImages.any((f) => f.path == initialFile.path)) {
                        selectedImages.add(initialFile);
                    }
                    selectionChanged = true;
                }
            }
        }
    }

    for(String assetId in selectedAssetIds) {
        if(allImages.any((a) => a.id == assetId)) {
            if(_selectedStatusNotifiers.containsKey(assetId) && !_selectedStatusNotifiers[assetId]!.value) {
                _selectedStatusNotifiers[assetId]!.value = true;
                selectionChanged = true;
            }
        }
    }


    if (selectionChanged) {
        setState(() {});
    }
  }

  Future<void> pickImagesNative() async {
    final picker = image_picker.ImagePicker();
    if (widget.allowMultiple) {
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        setState(() {
          for (var file in pickedFiles) {
            if (!selectedImages.any((selectedFile) => selectedFile.path == file.path)) {
              selectedImages.add(File(file.path));
            }
          }
        });
      }
    } else {
      final pickedFile = await picker.pickImage(source: image_picker.ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          selectedImages = [File(pickedFile.path)];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    // Determine if the complete button should be enabled
    bool canComplete = selectedAssetIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.selectImage),
        actions: [
          if (isLimitedAccess && Platform.isIOS)
            IconButton(
              icon: Icon(Icons.add_photo_alternate_outlined),
              // tooltip: l10n.addMorePhotos ?? 'Add more photos',
              tooltip: 'Add more photos',
              onPressed: () async {
                await PhotoManager.presentLimited();
                await checkPermissionAndLoadImages();
              },
            ),
          TextButton(
            child: Text(l10n.complete),
            onPressed: canComplete
                ? () {
                    _updateSelectedImagesFromAssetIds().then((_) {
                      Navigator.pop(context, selectedImages);
                    });
                  }
                : null,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _updateSelectedImagesFromAssetIds() async {
    List<File> newSelectedFiles = [];
    for (String assetId in selectedAssetIds) {
      File? file = imageCache[assetId];
      if (file == null) {
        AssetEntity? asset = allImages.firstWhere((a) => a.id == assetId, orElse: () => null as AssetEntity);
        if (asset != null) {
          file = await asset.file;
          if (file != null) {
            imageCache[assetId] = file;
          }
        }
      }
      if (file != null) {
        newSelectedFiles.add(file);
      }
    }
    selectedImages = newSelectedFiles;
  }

  Widget _buildBody() {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    if (isNoAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l10n.setImagePermissionInSettings, textAlign: TextAlign.center),
              SizedBox(height: 16),
              ElevatedButton(
                // child: Text(l10n.openSettings ?? 'Open Settings'),
                child: Text('Open Settings'),
                onPressed: () {
                  PhotoManager.openSetting();
                },
              )
            ],
          ),
        ),
      );
    } else if (isFullAccess || isLimitedAccess) {
      if (allImages.isEmpty) {
        bool hasActuallyCheckedAndIsEmpty = (isFullAccess || isLimitedAccess);

        if (hasActuallyCheckedAndIsEmpty) {
            if (_thumbnailFutures.isEmpty && currentPage == 0 && allImages.isEmpty) {
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  isLimitedAccess
                      // ? (l10n.noPhotosSelectedForLimitedAccess ?? 'No photos currently selected for app access. You can add more via the button in the top bar (iOS) or adjust in settings.')
                      // : (l10n.noPhotosFound ?? 'No photos found.'),
                      ? 'No photos currently selected for app access. You can add more via the button in the top bar (iOS) or adjust in settings.'
                      : 'No photos found.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
        } else {
             return Center(child: CircularProgressIndicator());
        }
      }
      return buildAllImagesGrid();
    } else {
      return Center(child: CircularProgressIndicator());
    }
  }

  Widget buildAllImagesGrid() {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) {
          loadAllImages();
        }
        return true;
      },
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: allImages.length,
        itemBuilder: (context, index) {
          return _buildImageItem(allImages[index]);
        },
      ),
    );
  }

  Widget buildSelectedImagesGrid() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: selectedImages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return GestureDetector(
            onTap: pickImagesNative,
            child: Container(
              color: Colors.grey[300],
              child: Icon(Icons.add, size: 50),
            ),
          );
        } else {
          return _buildSelectedImageItem(selectedImages[index - 1]);
        }
      },
    );
  }

  Widget _buildImageItem(AssetEntity asset) {
    final isSelectedNotifier = _selectedStatusNotifiers.putIfAbsent(asset.id, () => ValueNotifier(selectedAssetIds.contains(asset.id)));

    return FutureBuilder<typed_data.Uint8List?>(
      future: _thumbnailFutures[asset.id],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return ValueListenableBuilder<bool>(
            valueListenable: isSelectedNotifier,
            builder: (context, isSelected, _) {
              return GestureDetector(
                onTap: () async {
                  bool newSelectedState;

                  if (!widget.allowMultiple) {
                    if (_currentSingleSelectedAssetId == asset.id) {
                      return;
                    } else {
                      if (_currentSingleSelectedAssetId != null && _selectedStatusNotifiers.containsKey(_currentSingleSelectedAssetId)) {
                        _selectedStatusNotifiers[_currentSingleSelectedAssetId!]!.value = false;
                      }
                      newSelectedState = true;
                      isSelectedNotifier.value = true;
                    }
                  } else {
                    newSelectedState = !isSelectedNotifier.value;
                    isSelectedNotifier.value = newSelectedState;
                  }

                  File? originalFile;
                  if (newSelectedState || widget.allowMultiple) {
                    originalFile = await _getImageFile(asset);
                    if (originalFile == null) {
                      isSelectedNotifier.value = !newSelectedState;
                      if (!widget.allowMultiple && newSelectedState) {
                         if (_currentSingleSelectedAssetId != null && _currentSingleSelectedAssetId != asset.id && _selectedStatusNotifiers.containsKey(_currentSingleSelectedAssetId)) {
                         }
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppLocalizations.of(context)!.errorSelectingImage)),
                      );
                      return;
                    }
                  }

                  if (!widget.allowMultiple) {
                    if (newSelectedState && originalFile != null) {
                      selectedAssetIds.clear();
                      selectedImages.clear();
                      selectedAssetIds.add(asset.id);
                      selectedImages.add(originalFile);
                      _currentSingleSelectedAssetId = asset.id;
                    } else if (!newSelectedState && _currentSingleSelectedAssetId == asset.id) {
                      selectedAssetIds.remove(asset.id);
                      if (originalFile != null) selectedImages.removeWhere((f) => f.path == originalFile!.path);
                      _currentSingleSelectedAssetId = null;
                    } else if (newSelectedState && originalFile == null) {
                        _currentSingleSelectedAssetId = null;
                        selectedAssetIds.clear();
                        selectedImages.clear();
                    }
                  } else {
                    if (newSelectedState && originalFile != null) {
                      selectedAssetIds.add(asset.id);
                      if (!selectedImages.any((f) => f.path == originalFile?.path)) {
                        selectedImages.add(originalFile);
                      }
                    } else {
                      selectedAssetIds.remove(asset.id);
                      if (imageCache.containsKey(asset.id)){
                        selectedImages.removeWhere((file) => file.path == imageCache[asset.id]!.path);
                      }
                    }
                  }
                  setState(() {});
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                      ),
                      if (isSelected && widget.allowMultiple)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            padding: EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        } else if (snapshot.hasError) {
          return Container(
            color: Colors.red[100],
            child: Center(child: Icon(Icons.error_outline, color: Colors.red, size: 50)),
          );
        } else {
          return Container(color: Colors.grey[300]);
        }
      },
    );
  }

  Widget _buildSelectedImageItem(File image) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(image, fit: BoxFit.cover),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: () {
              setState(() {
                selectedImages.remove(image);
              });
            },
          ),
        ),
      ],
    );
  }

  Future<File?> _getImageFile(AssetEntity asset) async {
    if (imageCache.containsKey(asset.id)) {
      return imageCache[asset.id];
    }
    final file = await asset.file;
    if (file != null) {
      imageCache[asset.id] = file;
    }
    return file;
  }
}
