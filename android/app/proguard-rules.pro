# Guava's reflection-based Invokable/TypeToken code references classes that
# don't exist on Android (java.lang.reflect.AnnotatedType and friends). These
# code paths are never actually hit at runtime on Android, but R8 still flags
# them as "missing classes" in release/minified builds. Silence those.
-dontwarn java.lang.reflect.AnnotatedType
-dontwarn com.google.common.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn com.google.j2objc.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.lang.model.element.Modifier

# Keep Guava's core reflect classes so they're not stripped entirely if
# something in your dependency tree does actually touch them at runtime.
-keep class com.google.common.reflect.** { *; }