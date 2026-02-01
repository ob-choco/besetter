# Claude Code Guidelines for Mobile App

## Verification Commands

Use these commands to verify code changes (in order of preference):

### 1. Static Analysis (Fastest)
```bash
cd apps/mobile && flutter analyze
```
- Checks for compile errors, type errors, and lint issues
- No build required, runs in seconds
- **Use this as the primary verification method**

### 2. Code Generation (When using Riverpod/Freezed)
```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
```
- Generates `.g.dart` files for Riverpod providers
- Run after creating/modifying files with `@riverpod` annotations

### 3. Unit Tests
```bash
cd apps/mobile && flutter test
```
- Run when tests exist and are relevant to changes

## Do NOT Use

- **`flutter build apk`** - Android build environment is not stable
- **`flutter build ios`** - Requires macOS and Xcode setup
- **`flutter run`** - Requires connected device/emulator

## Code Style

- Use hooks_riverpod with riverpod_annotation for state management
- Prefer HookConsumerWidget over ConsumerStatefulWidget when using hooks
- Keep widgets small and focused (extract to separate files)
