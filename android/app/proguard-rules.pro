# --- Fix untuk flutter_local_notifications + Gson (Missing type parameter) ---
   -keepattributes Signature
   -keepattributes *Annotation*
   -keep class com.dexterous.flutterlocalnotifications.** { *; }
   -keep class com.google.gson.** { *; }
   -keep class * extends com.google.gson.reflect.TypeToken
   -keep class com.google.gson.reflect.TypeToken { *; }
   -dontwarn com.google.gson.**