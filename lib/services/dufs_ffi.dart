// dufs_ffi.dart — Dart FFI bindings for libdufs.so / dufs.dll / libdufs.dylib

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// C function signatures
typedef DufsStartNative =
    Int32 Function(Int32 argc, Pointer<Pointer<Utf8>> argv);
typedef DufsStopNative = Void Function();
typedef DufsIsRunningNative = Int32 Function();

// Dart function signatures
typedef DufsStart = int Function(int argc, Pointer<Pointer<Utf8>> argv);
typedef DufsStop = void Function();
typedef DufsIsRunning = int Function();

// Only directories created by this isolate may be removed after dlopen. Linux
// keeps the mapped inode alive after unlinking its private staging copy.
final _stagedDufsLibraries = <String, Directory>{};

/// Discard this isolate's private library copy if startup was canceled.
Future<void> discardResolvedDufsLibPath(String libPath) async {
  final staging = _stagedDufsLibraries.remove(libPath);
  if (staging == null) return;
  try {
    await staging.delete(recursive: true);
  } on FileSystemException {
    // OS temp cleanup can remove our directory if unlinking fails.
  }
}

Directory _createPrivateDufsTempDirectory() {
  // Dart's createTemp uses the process umask and can create mode 0777.
  // POSIX mkdtemp atomically creates mode 0700, including with umask 000.
  final template = p
      .join(Directory.systemTemp.path, 'fileinfra-libdufs-XXXXXX')
      .toNativeUtf8();
  try {
    final mkdtemp = DynamicLibrary.process()
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)
        >('mkdtemp');
    final result = mkdtemp(template);
    if (result == nullptr) {
      throw FileSystemException(
        'Could not create private dufs staging directory',
        Directory.systemTemp.path,
      );
    }
    return Directory(result.toDartString());
  } finally {
    malloc.free(template);
  }
}

class DufsFfi {
  DynamicLibrary? _lib;
  DufsStart? _start;
  DufsStop? _stop;
  DufsIsRunning? _isRunning;

  /// Load the shared library from the given path.
  void load(String libPath) {
    try {
      _lib = DynamicLibrary.open(libPath);
      _start = _lib!.lookupFunction<DufsStartNative, DufsStart>('dufs_start');
      _stop = _lib!.lookupFunction<DufsStopNative, DufsStop>('dufs_stop');
      _isRunning = _lib!.lookupFunction<DufsIsRunningNative, DufsIsRunning>(
        'dufs_is_running',
      );
    } finally {
      final staging = _stagedDufsLibraries.remove(libPath);
      if (staging != null) {
        try {
          staging.deleteSync(recursive: true);
        } on FileSystemException {
          // OS temp cleanup can remove our directory if unlinking fails.
        }
      }
    }
  }

  /// Start the dufs server with an argv array.
  /// Returns 0 on success, -1 on error.
  int start(List<String> args) {
    if (_start == null) throw StateError('DufsFfi not loaded');
    final argc = args.length;
    final argv = calloc<Pointer<Utf8>>(argc);
    final owned = <Pointer<Utf8>>[];
    try {
      for (var i = 0; i < argc; i++) {
        final ptr = args[i].toNativeUtf8();
        owned.add(ptr);
        argv[i] = ptr;
      }
      return _start!(argc, argv);
    } finally {
      for (final ptr in owned) {
        malloc.free(ptr);
      }
      calloc.free(argv);
    }
  }

  /// Stop the dufs server.
  void stop() {
    if (_stop == null) throw StateError('DufsFfi not loaded');
    _stop!();
  }

  /// Check if the server is running.
  bool isRunning() {
    if (_isRunning == null) return false;
    return _isRunning!() == 1;
  }

  bool get isLoaded => _lib != null;
}

/// Resolve the path to the dufs shared library for the current platform.
Future<String> resolveDufsLibPath() async {
  if (Platform.isLinux) {
    // Copy out of AppImage's FUSE mount so dufs can open its library reliably.
    final exeDir = Directory.fromUri(
      Uri.file(Platform.resolvedExecutable),
    ).parent.path;
    final libPath = '$exeDir/libdufs.so';
    if (exeDir.contains('.mount_')) {
      // Never reuse or sweep shared temp files belonging to other launches.
      final staging = _createPrivateDufsTempDirectory();
      final tmpLib = p.join(staging.path, 'libdufs.so');
      try {
        await File(libPath).copy(tmpLib);
        _stagedDufsLibraries[tmpLib] = staging;
        return tmpLib;
      } catch (_) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Preserve the original copy error.
        }
        rethrow;
      }
    }
    return libPath;
  } else if (Platform.isMacOS) {
    final exeDir = Directory.fromUri(
      Uri.file(Platform.resolvedExecutable),
    ).parent.path;
    return '$exeDir/libdufs.dylib';
  } else if (Platform.isWindows) {
    // Windows: extract from asset to app data dir
    final exeDir = Directory.fromUri(
      Uri.file(Platform.resolvedExecutable),
    ).parent.path;
    return '$exeDir/dufs.dll';
  }
  throw UnsupportedError(
    'Platform not supported for FFI: ${Platform.operatingSystem}',
  );
}
