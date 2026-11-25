# Flutter Background Service
-keep class id.flutter.flutter_background_service.** { *; }
-keep class id.flutter.flutter_background_service_android.** { *; }
-keep class id.flutter.flutter_background_service_plugin.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# File Picker & URL Launcher
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }

# Battery Plus & Device Info Plus
-keep class dev.fluttercommunity.plus.battery.** { *; }
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# Package Info Plus
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# Open Filex
-keep class com.crazecoder.openfilex.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# Dio
-dontwarn okhttp3.**
-dontwarn okio.**

# Gson (dipakai flutter_local_notifications lewat refleksi TypeToken).
# Tanpa ini R8 membuang info generic -> "RuntimeException: Missing type parameter".
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.gson.** { *; }

# Kode aplikasi sendiri
-keep class com.ciko.build.** { *; }

# Preserve Line Numbers
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile