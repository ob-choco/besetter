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
String _$routesHash() => r'a6c47c703396e3e61f3ba1017a2319b7d5d4e583';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$Routes extends BuildlessAutoDisposeAsyncNotifier<RoutesState> {
  late final String? type;

  FutureOr<RoutesState> build({
    String? type,
  });
}

/// See also [Routes].
@ProviderFor(Routes)
const routesProvider = RoutesFamily();

/// See also [Routes].
class RoutesFamily extends Family<AsyncValue<RoutesState>> {
  /// See also [Routes].
  const RoutesFamily();

  /// See also [Routes].
  RoutesProvider call({
    String? type,
  }) {
    return RoutesProvider(
      type: type,
    );
  }

  @override
  RoutesProvider getProviderOverride(
    covariant RoutesProvider provider,
  ) {
    return call(
      type: provider.type,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'routesProvider';
}

/// See also [Routes].
class RoutesProvider
    extends AutoDisposeAsyncNotifierProviderImpl<Routes, RoutesState> {
  /// See also [Routes].
  RoutesProvider({
    String? type,
  }) : this._internal(
          () => Routes()..type = type,
          from: routesProvider,
          name: r'routesProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$routesHash,
          dependencies: RoutesFamily._dependencies,
          allTransitiveDependencies: RoutesFamily._allTransitiveDependencies,
          type: type,
        );

  RoutesProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.type,
  }) : super.internal();

  final String? type;

  @override
  FutureOr<RoutesState> runNotifierBuild(
    covariant Routes notifier,
  ) {
    return notifier.build(
      type: type,
    );
  }

  @override
  Override overrideWith(Routes Function() create) {
    return ProviderOverride(
      origin: this,
      override: RoutesProvider._internal(
        () => create()..type = type,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        type: type,
      ),
    );
  }

  @override
  AutoDisposeAsyncNotifierProviderElement<Routes, RoutesState> createElement() {
    return _RoutesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is RoutesProvider && other.type == type;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, type.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin RoutesRef on AutoDisposeAsyncNotifierProviderRef<RoutesState> {
  /// The parameter `type` of this provider.
  String? get type;
}

class _RoutesProviderElement
    extends AutoDisposeAsyncNotifierProviderElement<Routes, RoutesState>
    with RoutesRef {
  _RoutesProviderElement(super.provider);

  @override
  String? get type => (origin as RoutesProvider).type;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
