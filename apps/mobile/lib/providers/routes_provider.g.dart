// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routes_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$routesTotalCountHash() => r'f8f5f86793ddb14fc671d90db1bd4a2d62a402f7';

/// See also [routesTotalCount].
@ProviderFor(routesTotalCount)
final routesTotalCountProvider = AutoDisposeFutureProvider<int>.internal(
  routesTotalCount,
  name: r'routesTotalCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$routesTotalCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RoutesTotalCountRef = AutoDisposeFutureProviderRef<int>;
String _$routesHash() => r'12162fd24d7004842d5b0c6b40e5d3418df87e79';

/// See also [Routes].
@ProviderFor(Routes)
final routesProvider =
    AutoDisposeAsyncNotifierProvider<Routes, RoutesState>.internal(
  Routes.new,
  name: r'routesProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$routesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Routes = AutoDisposeAsyncNotifier<RoutesState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
