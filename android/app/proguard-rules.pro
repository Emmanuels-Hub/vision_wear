# Flutter engine entry points.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# TensorFlow Lite / ultralytics_yolo: the interpreter resolves these
# reflectively, so R8 must not rename or strip them.
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.**
-keep class com.ultralytics.** { *; }
-dontwarn com.ultralytics.**

# ML Kit models are loaded by name.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Speech recognition and TTS plugin bridges.
-keep class com.csdcorp.speech_to_text.** { *; }

# Keep annotations used for reflection by the above.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
