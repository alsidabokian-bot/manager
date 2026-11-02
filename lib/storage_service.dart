import 'package:flutter/services.dart';

class DiskSpace {
  const DiskSpace(this.total, this.free);
  final int total;
  final int free;
  int get used => total - free;
  double get usedFraction => total == 0 ? 0 : used / total;
}

/// جسر إلى كود أندرويد: الإذن، ومجلدات النظام، ومساحة القرص.
class StorageService {
  StorageService._();

  static const _channel = MethodChannel('com.tamreen.filemanager/storage');

  static const _fallbackRoot = '/storage/emulated/0';
  static const Map<String, String> _fallbackRoots = {
    'internal': _fallbackRoot,
    'downloads': '$_fallbackRoot/Download',
    'pictures': '$_fallbackRoot/Pictures',
    'dcim': '$_fallbackRoot/DCIM',
    'documents': '$_fallbackRoot/Documents',
    'music': '$_fallbackRoot/Music',
    'movies': '$_fallbackRoot/Movies',
  };

  static Future<bool> hasAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// يفتح إعدادات النظام (أو نافذة الإذن في الأجهزة القديمة).
  static Future<void> requestAccess() async {
    try {
      await _channel.invokeMethod<void>('requestAccess');
    } catch (_) {}
  }

  /// مسارات التخزين الداخلي والمجلدات الشائعة.
  static Future<Map<String, String>> roots() async {
    try {
      final m = await _channel.invokeMapMethod<String, String>('roots');
      if (m != null && m.isNotEmpty) return m;
    } catch (_) {}
    return _fallbackRoots;
  }

  static Future<DiskSpace?> diskSpace(String path) async {
    try {
      final m = await _channel.invokeMapMethod<String, int>(
        'diskSpace',
        {'path': path},
      );
      if (m == null) return null;
      return DiskSpace(m['total'] ?? 0, m['free'] ?? 0);
    } catch (_) {
      return null;
    }
  }

  // ---------- الخدمة الأمامية والإشعار ----------

  static Future<void> startService(String title, String text) async {
    try {
      await _channel.invokeMethod<void>('startService', {'title': title, 'text': text});
    } catch (_) {}
  }

  /// progress من 0 إلى 100، أو -1 لشريط غير محدد.
  static Future<void> updateNotification(String title, String text, int progress) async {
    try {
      await _channel.invokeMethod<void>(
        'updateNotification',
        {'title': title, 'text': text, 'progress': progress},
      );
    } catch (_) {}
  }

  static Future<void> stopService() async {
    try {
      await _channel.invokeMethod<void>('stopService');
    } catch (_) {}
  }

  // ---------- تحسين البطارية ----------

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBattery') ?? true;
    } catch (_) {
      return true; // إن تعذّر الفحص لا نزعج المستخدم
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod<void>('requestIgnoreBattery');
    } catch (_) {}
  }

  // ---------- فتح الملفات ومشاركتها ----------

  /// يفتح الملف بتطبيق آخر. يُرجع نص الخطأ أو null عند النجاح.
  static Future<String?> openFile(String path) async {
    try {
      await _channel.invokeMethod<bool>('openFile', {'path': path});
      return null;
    } on PlatformException catch (e) {
      return e.message ?? 'تعذّر فتح الملف';
    } catch (_) {
      return 'تعذّر فتح الملف';
    }
  }

  /// يشارك ملفات (المجلدات لا تُشارك). يُرجع نص الخطأ أو null.
  static Future<String?> shareFiles(List<String> paths) async {
    try {
      await _channel.invokeMethod<bool>('shareFiles', {'paths': paths});
      return null;
    } on PlatformException catch (e) {
      return e.message ?? 'تعذّرت المشاركة';
    } catch (_) {
      return 'تعذّرت المشاركة';
    }
  }
}
