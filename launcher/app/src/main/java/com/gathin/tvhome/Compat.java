package com.gathin.tvhome;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.net.ConnectivityManager;
import android.os.Build;
import android.os.UserManager;
import android.view.View;

import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * The calls the launcher makes that Android only added after 6.0 (API 23), each with the older path it
 * stands in for. Upstream needs none of this: its minSdk is 26, above every API named here, and each
 * branch below is the call the launcher already made. They exist so that {@code -PlauncherMinSdk=23}
 * can build the same source for older sets (Hisense VIDAA, Android 6.0), where the plain call is a
 * NoSuchMethodError at startup rather than a warning.
 */
final class Compat {
    private Compat() {}

    /** {@code View#forceHasOverlappingRendering}, API 29 (Android 10): below it the flag does not exist and the
     *  view keeps drawing through an offscreen buffer. A slower fade, not a broken one. Upstream calls it
     *  unguarded, which its own minSdk 26 does not excuse either - on a set below Android 10 the call lands on
     *  a method that is not there and the launcher dies in onCreate with
     *  "NoSuchMethodError: forceHasOverlappingRendering". */
    static void noOverlappingRendering(View view) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) view.forceHasOverlappingRendering(false);
    }

    /** {@code UserManager#isUserUnlocked}, API 24. Before 7.0 there is no direct-boot storage, so the user is
     *  unlocked from the first frame and credential-protected storage can be read straight away. */
    static boolean isUserUnlocked(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return true;
        UserManager users = (UserManager) context.getSystemService(Context.USER_SERVICE);
        return users == null || users.isUserUnlocked();
    }

    /** {@code AccessibilityService#disableSelf}, API 24. Below it there is no way for an enabled service to
     *  stand itself down, so it stays on: the guard it belongs to is an Android 11 feature and never runs
     *  that far back anyway. */
    static void disableSelf(AccessibilityService service) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) service.disableSelf();
    }

    /** {@code Configuration#getLocales}, API 24: the single locale field before it. */
    @SuppressWarnings("deprecation")
    static Locale firstLocale(Configuration configuration) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) return configuration.getLocales().get(0);
        return configuration.locale != null ? configuration.locale : Locale.getDefault();
    }

    /** {@code TvInputInfo#isHidden}, API 24: before it no input can be hidden from the menu. */
    static boolean isHidden(TvInputInfo info, Context context) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && info.isHidden(context);
    }

    /** {@code TvInputInfo#loadCustomLabel}, API 24: before it the owner cannot have named an input. */
    static CharSequence customLabel(TvInputInfo info, Context context) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N ? info.loadCustomLabel(context) : null;
    }

    /** {@code Bitmap.Config#HARDWARE}, API 26: below it the copy stays in software memory, so one more
     *  upload to the GPU when the wallpaper returns, not a wrong picture. */
    static Bitmap.Config hardwareConfig() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? Bitmap.Config.HARDWARE : Bitmap.Config.ARGB_8888;
    }

    /** {@code ConnectivityManager#registerDefaultNetworkCallback}, API 24. Below it the manager has no default
     *  callback to register, so the launcher simply goes without the online/offline banner. */
    static void registerDefaultNetworkCallback(ConnectivityManager manager, ConnectivityManager.NetworkCallback callback) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return;
        manager.registerDefaultNetworkCallback(callback);
    }

    /** {@code PackageManager#getChangedPackages}, API 24. Below it the manager cannot say what changed, so the
     *  caller treats the grid as up to date and rebuilds it the slow way instead. */
    static android.content.pm.ChangedPackages changedPackages(PackageManager manager, int sequence) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null;
        return manager.getChangedPackages(sequence);
    }

    /**
     * The TV input framework, or null on a set that does not have one. Every Android TV has it; Hisense's
     * VIDAA (Android 6) does not, and its {@code getSystemService} hands back a TvInputManager whose binder
     * is null rather than answering null, so the null check the launcher already does passes and the first
     * call throws. Probing here keeps the Inputs menu empty on those sets instead of taking Home down.
     */
    static TvInputManager tvInputs(Context context) {
        TvInputManager tim = (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
        if (tim == null) return null;
        try {
            tim.getTvInputList();
            return tim;
        } catch (RuntimeException | NoClassDefFoundError absent) {
            return null;
        }
    }

    /**
     * The list of inputs, or an empty list on a set with no usable TV input framework. The manager is probed
     * once and the answer kept: on a Hisense VIDAA the binder behind it is null and every call throws, so asking
     * again each time would throw again each time.
     */
    static List<TvInputInfo> tvInputList(Context context, TvInputManager manager) {
        if (manager == null) return Collections.emptyList();
        try {
            List<TvInputInfo> list = manager.getTvInputList();
            return list == null ? Collections.emptyList() : list;
        } catch (RuntimeException | NoClassDefFoundError absent) {
            return Collections.emptyList();
        }
    }
}
