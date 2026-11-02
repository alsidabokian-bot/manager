# مدير الملفات

مدير ملفات لأندرويد مبني بـ Flutter. النسخة النهائية: الأذونات والتصفح ومحرك النسخ والنقل والتحديد المتعدد والحذف وإعادة التسمية والبحث والترتيب وعرض القائمة والشبكة ومعاينة الصور والنصوص وفتح الملفات ومشاركتها.

## البناء
GitHub: Actions ← **Build Flutter APK** ← Run workflow، واكتب رقم إصدار Flutter متاحًا (مثل `3.35.0` أو أي إصدار stable حديث؛ الافتراضي في الملف جاء من القالب ولم يُتحقق منه). محليًا: `flutter pub get` ثم `flutter build apk --release`.

## الملفات
| الملف | الوظيفة |
|---|---|
| `lib/main.dart` | نقطة البدء |
| `lib/permission_gate.dart` | شاشة إذن الوصول إلى الملفات |
| `lib/home_screen.dart` | التخزين الداخلي والوصول السريع |
| `lib/browser_screen.dart` | تصفح المجلدات ومسار التنقل |
| `lib/file_models.dart` | قراءة المجلدات (في خيط منفصل) وأنواع الملفات |
| `lib/transfer_worker.dart` | محرك النسخ والنقل (خيط منفصل، ملفات `.part`، تحقق، استئناف) |
| `lib/transfer_manager.dart` | قائمة الانتظار والتحكم والإشعار |
| `lib/transfer_screen.dart` | شاشة التقدم والتقرير |
| `lib/file_ops.dart` | حذف وإعادة تسمية وإنشاء مجلد والتحقق من الأسماء |
| `lib/file_dialogs.dart` | حوارات الاسم والتأكيد والانتظار |
| `lib/file_search.dart` | البحث بالاسم في المجلدات الفرعية (خيط منفصل قابل للإلغاء) |
| `lib/view_prefs.dart` و`lib/view_options.dart` | الترتيب وطريقة العرض |
| `lib/image_viewer.dart` و`lib/text_viewer.dart` | معاينة الصور (تكبير وتمرير) والنصوص |
| `lib/file_open.dart` | اختيار طريقة فتح الملف (داخلي أو تطبيق آخر) ومشاركته |
| `lib/settings_screen.dart` و`lib/app_settings.dart` | الإعدادات المحفوظة (المظهر، المخفية، التحقق العميق، الأذونات) |
| `lib/storage_service.dart` | جسر إلى أندرويد (الإذن، المسارات، المساحة) |
| `android/.../MainActivity.kt` و`TransferService.kt` | كود أندرويد (الجسر والخدمة الأمامية والإشعار) |

## ملاحظة
إذن «الوصول إلى كل الملفات» يعمل عند تثبيت الـAPK مباشرة، لكن Google Play يقيّده ويشترط مبررًا.
