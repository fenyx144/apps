# VOSK / JNA (requerido por vosk_flutter)
-keep class com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }

# JNA referencia java.awt (solo existe en escritorio); en Android no existen, ignorar.
-dontwarn java.awt.**
