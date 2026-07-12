# Flutter's default rules reference the Play Core deferred-components API,
# which this app does not ship; silence the R8 missing-class errors.
-dontwarn com.google.android.play.core.**
