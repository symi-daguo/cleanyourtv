# Rules that only the Android 6 build needs. Kept out of proguard-rules.pro so the minSdk 26 release is not
# made bigger by them: that APK never desugars a lambda, so -dontoptimize would cost it size for nothing.
#
# Below API 24 the JVM has no invoke-custom, so D8 rewrites a lambda into a synthetic class it calls through a
# MethodHandle; R8 sees those classes as unreferenced and strips them, and the app dies on the first key press
# with "NoClassDefFoundError: com.gathin.tvhome.RemoteKeys$$ExternalSyntheticLambda1".
-keep class **$$ExternalSyntheticLambda { *; }
-keep class **$$Lambda { *; }
# R8's optimiser rewrites the desugared lambda bodies in a way the Android 6 class loader refuses, so the class
# is in the dex but cannot be linked. Leaving the optimisation alone costs this build a few KB and keeps it working.
-dontoptimize
