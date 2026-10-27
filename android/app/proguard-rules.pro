# Release builds are shrunk by R8. flutter_local_notifications stores its
# scheduled notifications (the daily-challenge reminder) as JSON through
# Gson's TypeToken, which needs the generic signatures R8 strips: without
# these rules the app crashed on start and on boot with "TypeToken must be
# created with a type argument".
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.** { *; }
