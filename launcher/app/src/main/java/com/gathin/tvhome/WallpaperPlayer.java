package com.gathin.tvhome;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Path;
import android.graphics.PathMeasure;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.TextView;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Displays and rotates a theme's local wallpaper images while Home is visible. */
final class WallpaperPlayer {
    /** The app context, for reading the bundled pictures out of the assets. */
    private final Context context;
    private final FrameLayout root;
    private final ImageView image;
    private final int backgroundColor;
    private final List<File> files;
    private final long interval;
    private final String order;
    private final SharedPreferences preferences;
    private final ExecutorService decoder = Executors.newSingleThreadExecutor();
    private final Random random = new Random();
    private final int width;
    /** config wallpaper_true_color: ARGB_8888 instead of RGB_565. */
    private final Bitmap.Config bitmapConfig;
    private final int height;
    /** wallpaper_dim as an ARGB black, painted into each picture once instead of a full-screen shade view. */
    private final int dimColor;
    /** The picture on screen, released once the next one has been drawn. */
    private Bitmap current;
    private boolean active;
    private boolean closed;
    private boolean loading;
    private String displayed = "";
    /** wallpaper_captions: the shown picture's name from wallpapers/captions.txt; null when off or there are none. */
    private final TextView caption;
    private final Map<String, String> names;
    /** wallpaper_moods: the collection's groups by time of day; empty rotates through all of it. */
    private final Map<String, Set<String>> moods;
    /** config.xml latitude and longitude for the sun's times, and today's {sunrise, sunset} once worked out. */
    private final String latitude, longitude;
    private LocalDate sunDay;
    private int[] sun;
    /** config.xml wallpaper_motion: slow Ken Burns drift instead of a still picture. */
    private boolean motion;
    /** A video layer covers the picture, so the drift under it would only burn frames. */
    private boolean motionBlocked;
    /** Pictures bundled in the low-SDK build for a set whose external storage is gone; empty otherwise. */
    private final List<String> builtinAssets = new ArrayList<>();
    /** Index of the bundled picture on screen. */
    private int builtinIndex;
    /** The path the picture walks, redrawn every lap. */
    private Path driftPath;
    private final PathMeasure driftMeasure = new PathMeasure();
    private final float[] driftPos = new float[2];
    private float driftLength;
    /** How far along the path the picture is, 0 to 1. */
    private float driftFraction;
    /** The fraction of the previous lap, so a new one can be told from the old. */
    private float lastFraction;
    /** When the current lap began, in the clock the frames are timed against. */
    private long driftStartedAt;
    /** Length of one lap of the drift. */
    private static final long MOTION_MS = 120000L;
    /** The picture is always scaled by at least this much, so there is room to pan without showing an edge. */
    private static final float MIN_SCALE = 1.28f;

    WallpaperPlayer(Context context, FrameLayout root, Config config) {
        this.context = context;
        this.root = root;
        backgroundColor = config.backgroundColor;
        files = new ArrayList<>(config.wallpapers);
        interval = config.wallpaperRotationMinutes * 60_000L;
        bitmapConfig = config.wallpaperTrueColor ? Bitmap.Config.ARGB_8888 : Bitmap.Config.RGB_565;
        // The dim is painted into the picture (decode), so no full-screen shade layer is drawn on every frame.
        dimColor = config.wallpaperDim > 0 ? (config.wallpaperDim * 255 / 100) << 24 : 0;
        order = config.wallpaperOrder;
        preferences = context.getSharedPreferences("wallpaper_rotation", Context.MODE_PRIVATE);
        moods = config.wallpaperMoods;
        latitude = moods.isEmpty() ? "" : context.getString(R.string.latitude);
        longitude = moods.isEmpty() ? "" : context.getString(R.string.longitude);
        // Playback state belongs to one collection. Changing the collection starts from its first
        // picture instead of resuming a filename that belonged to the previous one.
        String collection = collectionKey(files);
        if (!collection.equals(preferences.getString("collection", ""))) {
            preferences.edit().putString("collection", collection)
                    .remove("image").remove("changed").apply();
        }
        DisplayMetrics metrics = context.getResources().getDisplayMetrics();
        width = metrics.widthPixels;
        height = metrics.heightPixels;
        image = new ImageView(context);
        image.setScaleType(ImageView.ScaleType.CENTER_CROP);
        image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        names = config.wallpaperCaptions && config.wallpaperEnabled && !files.isEmpty()
                ? WallpaperCaptions.read(files.get(0).getParentFile()) : Collections.emptyMap();
        caption = names.isEmpty() ? null : makeCaption(context, root);
        motion = config.wallpaperMotion;
        if (config.wallpaperEnabled && !files.isEmpty()) {
            root.addView(image, 0, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
            showFirst();
        } else if (context.getExternalFilesDir(null) == null) {
            // No external storage at all (Hisense VIDAA: /sdcard is a symlink to a mount that is not there), so neither a
            // pushed collection nor a config.json can arrive. The low-SDK build bundles a few pictures in assets for
            // exactly this case; they rotate on their own clock, one a minute, and carry the drift by default because
            // no key can ever be sent to turn it on.
            try {
                String[] bundled = context.getAssets().list("wallpapers");
                if (bundled != null) {
                    Arrays.sort(bundled);
                    builtinAssets.addAll(Arrays.asList(bundled));
                }
            } catch (IOException ignored) {
                // An empty list is the same as no fallback: Home keeps its plain colour.
            }
            if (!builtinAssets.isEmpty()) {
                Bitmap first = decodeAsset(builtinAssets.get(0));
                if (first != null) {
                    root.addView(image, 0, new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
                    motion = true;
                    show(first);
                }
            }
        }
    }

    /**
     * The picture Home opens with is decoded right here, on the main thread, as the single wallpaper always was:
     * Home's first frame already has it instead of drawing the plain colour and the picture popping in later.
     * Only the later changes of a rotation decode in the background.
     */
    private void showFirst() {
        String previous = preferences.getString("image", "");
        List<File> playable = playable();
        File first = WallpaperRotation.find(playable, previous);
        if (first == null) first = WallpaperRotation.pick(playable, previous, order, random);
        while (first != null) {
            Bitmap bitmap = decode(first);
            if (bitmap != null) {
                show(bitmap);
                // The picture covers the whole screen: the root's plain colour under it is overdraw.
                root.setBackground(null);
                displayed = first.getName();
                showCaption(false);
                if (!displayed.equals(previous)) {
                    preferences.edit().putString("image", displayed)
                            .putLong("changed", System.currentTimeMillis()).apply();
                }
                return;
            }
            files.remove(first);   // unreadable or over 4K: try another, or keep the plain colour
            playable = playable();
            first = WallpaperRotation.pick(playable, previous, order, random);
        }
    }

    void start() {
        active = true;
        // onTrimMemory drops the picture when Home goes behind another app - opening a heavy one like an ambient-light
        // controller is enough. Without this the set came back to a bare background colour, because the rotation
        // still had time left on it and so had no reason to load anything: the drift then ran over an empty view,
        // which is what looked like the background "no longer being smooth".
        if (current == null) {
            if (!files.isEmpty()) {
                showFirst();
            } else if (!builtinAssets.isEmpty()) {
                Bitmap again = decodeAsset(builtinAssets.get(builtinIndex));
                if (again != null) show(again);
            }
        }
        if (motion) startMotion();
        update();
    }

    void stop() {
        active = false;
        image.removeCallbacks(this::stepDrift);
    }

    /**
     * Stops the drift while something else covers the picture. The picture keeps its place underneath and comes back
     * moving when the layer goes: measured over three minutes on a Hisense VIDAA, letting the drift run under a
     * video cost about a third of the frames.
     */
    void setMotionBlocked(boolean blocked) {
        if (motionBlocked == blocked) return;
        motionBlocked = blocked;
        if (blocked) image.removeCallbacks(this::stepDrift);
        else if (active) startMotion();
    }

    /**
     * Lets the picture go when a video layer has taken the screen. The bitmap is one copy in GPU memory and
     * the video's decoder is another buffer; keeping both costs a few megabytes on a set with 1 GB of RAM for
     * something nobody can see.
     */
    void releasePicture() {
        image.removeCallbacks(this::stepDrift);
        // Aerial (HaloTV's base) found this on a Hisense VIDAA MTK9652: the decoder fails at times and
        // leaves the video plane black for seconds. Keep the picture's bitmap but hide it - three or
        // four MB buys an instant fallback, and the drift is stopped so it costs no frames.
        image.setVisibility(View.GONE);
    }

    /** The video failed: show the picture again at once, no decoding and no black plane. */
    void restorePicture() {
        image.setVisibility(View.VISIBLE);
    }

    /** True when a picture is on screen; Home uses it to keep the glow out of the way of a photo. */
    boolean hasPicture() {
        return current != null;
    }

    /**
     * The drift, along a path that is drawn afresh every lap.
     *
     * Two things were wrong before. The track was a single direction with REVERSE, so the picture retraced the same
     * diagonal for as long as it was up. Now a lap is a chain of random quadratic curves, drawn once per lap, so the
     * path is different every time and no two laps trace the same line.
     *
     * The picture is placed by the wall clock rather than by an animator's fraction: this board has a ~133 ms hole in
     * the frame timeline every eleven frames, and with a fraction the picture stopped dead for those frames and then
     * carried on from where it had been - which reads as a jolt. With the clock a skipped frame is a step to the right
     * position instead of a stall followed by a catch-up.
     */
    private void startMotion() {
        image.removeCallbacks(this::stepDrift);
        if (!motion || motionBlocked) {
            image.setScaleX(1f);
            image.setScaleY(1f);
            image.setTranslationX(0f);
            image.setTranslationY(0f);
            return;
        }
        buildDriftPath(0f, 0f);
        driftStartedAt = SystemClock.uptimeMillis();
        image.postOnAnimation(this::stepDrift);
    }

    /** One step: where the clock says the picture should be by now. */
    private void stepDrift() {
        if (!motion || closed || !active || motionBlocked) return;
        long now = SystemClock.uptimeMillis();
        float fraction = ((now - driftStartedAt) % MOTION_MS) / (float) MOTION_MS;
        onDrift(fraction);
        image.postOnAnimation(this::stepDrift);
    }

    /**
     * A closed chain of random curves, starting where the picture currently is and ending back there. Because it
     * begins and ends at the same spot, a new path can be swapped in the moment a lap ends without the picture
     * jumping: the walk carries on from exactly where it was, but along a different line.
     */
    private void buildDriftPath(float fromX, float fromY) {
        // The picture is scaled up so it is always wider and taller than the screen, and the walk is kept inside
        // what that margin allows. A path that wandered further would slide the edge of the picture into view and
        // leave a black strip along one side, which is what the drift must never do.
        float marginX = width * (1f - 1f / MIN_SCALE) * 0.5f * 0.55f;
        float marginY = height * (1f - 1f / MIN_SCALE) * 0.5f * 0.55f;
        Path path = new Path();
        float x = fromX, y = fromY;
        path.moveTo(x, y);
        for (int i = 0; i < 5; i++) {
            // Nudged towards a random spot inside the margin, never past it.
            float targetX = (random.nextBoolean() ? 1 : -1) * marginX * random.nextFloat();
            float targetY = (random.nextBoolean() ? 1 : -1) * marginY * random.nextFloat();
            float nextX = clamp(x + (targetX - x) * 0.55f, -marginX, marginX);
            float nextY = clamp(y + (targetY - y) * 0.55f, -marginY, marginY);
            // A curve, not a corner. Straight segments made the picture change direction in one frame at every bend,
            // and the eye reads that as a jolt; a quadratic through a point near the middle keeps the heading
            // continuous while still letting the line wander anywhere inside the margin.
            float cx = (x + nextX) * 0.5f + (random.nextFloat() - 0.5f) * marginX * 0.5f;
            float cy = (y + nextY) * 0.5f + (random.nextFloat() - 0.5f) * marginY * 0.5f;
            path.quadTo(cx, cy, nextX, nextY);
            x = nextX; y = nextY;
        }
        path.quadTo(x, y, fromX, fromY);   // back to where it started, so the lap joins up
        driftPath = path;
        driftMeasure.setPath(path, true);
        driftLength = driftMeasure.getLength();
    }

    /** Walks the path at the given fraction of a lap and moves the picture with it. */
    private void onDrift(float fraction) {
        if (driftLength <= 0f) return;
        // A lap that has just begun is a new one: draw a fresh line from here, so no two laps are the same.
        if (fraction < lastFraction) {
            driftMeasure.getPosTan(driftLength, driftPos, null);
            buildDriftPath(driftPos[0], driftPos[1]);
        }
        lastFraction = fraction;
        driftMeasure.getPosTan(fraction * driftLength, driftPos, null);
        image.setTranslationX(driftPos[0]);
        image.setTranslationY(driftPos[1]);
        // No breathing zoom on top of the pan. A few percent of scale moves every pixel of a full-screen picture at
        // once, which reads as a much bigger change than the pan itself; measured, it was three quarters of the
        // frame-to-frame difference. The picture is scaled once, by MIN_SCALE, and then only walked around.
        image.setScaleX(MIN_SCALE);
        image.setScaleY(MIN_SCALE);
    }

    private static float clamp(float value, float low, float high) {
        return value < low ? low : (value > high ? high : value);
    }

    /** Drops the wallpaper texture when Home is hidden and Android asks the process to free memory. */
    void releaseForMemoryPressure() {
        if (current == null) return;
        image.setImageDrawable(null);
        // The renderer may still have a queued frame that references this hardware bitmap. Drop our references and
        // let Android reclaim its native buffer after rendering releases it instead of recycling it mid-frame.
        current = null;
        displayed = "";
        root.setBackgroundColor(backgroundColor);
    }

    /** The pictures the rotation picks from now: wallpaper_moods' group for the time of day, or the whole collection. */
    private List<File> playable() {
        if (moods.isEmpty()) return files;
        LocalDateTime now = LocalDateTime.now();
        if (!now.toLocalDate().equals(sunDay)) {
            sunDay = now.toLocalDate();
            sun = WallpaperMood.sun(sunDay, latitude, longitude, ZoneId.systemDefault());
        }
        return WallpaperMood.select(files, moods, WallpaperMood.timeOfDay(now.getHour() * 60 + now.getMinute(), sun[0], sun[1]));
    }

    void close() {
        active = false;
        closed = true;
        image.removeCallbacks(this::stepDrift);
        decoder.shutdownNow();
    }

    void update() {
        if (!active || closed) return;
        if (files.isEmpty()) {
            advanceBuiltin();
            return;
        }
        if (loading) return;
        String previous = preferences.getString("image", "");
        // A picture outside the time of day's group (the group changed) is replaced at once, not after the interval.
        List<File> playable = playable();
        File selected = WallpaperRotation.find(playable, previous);
        long changed = preferences.getLong("changed", 0);
        if (selected == null || WallpaperRotation.due(changed, System.currentTimeMillis(), interval)) {
            selected = WallpaperRotation.pick(playable, previous, order, random);
        }
        if (selected == null || selected.getName().equals(displayed)) return;
        File next = selected;
        loading = true;
        decoder.execute(() -> {
            Bitmap bitmap = decode(next);
            root.post(() -> {
                loading = false;
                if (closed || !active) {
                    if (bitmap != null) bitmap.recycle();
                    return;
                }
                if (bitmap == null) {
                    files.remove(next);
                    Log.w("TvHome.Wallpaper", "Skipping unreadable image: " + next.getName());
                    update();
                    return;
                }
                show(bitmap);
                displayed = next.getName();
                showCaption(true);
                if (!displayed.equals(previous) || changed == 0) {
                    preferences.edit().putString("image", displayed)
                            .putLong("changed", System.currentTimeMillis()).apply();
                }
            });
        });
    }

    /**
     * Small light text under the top-right buttons, above everything else and never focusable. It sits where the
     * top bar ends in every layout, so it does not cover the clock, the stats line or the tiles.
     */
    private static TextView makeCaption(Context context, FrameLayout root) {
        float dp = context.getResources().getDisplayMetrics().density;
        TextView text = new TextView(context);
        text.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        text.setTextColor(0xD9FFFFFF);
        text.setShadowLayer(6 * dp, 0, dp, 0xCC000000);
        text.setSingleLine(true);
        text.setEllipsize(TextUtils.TruncateAt.END);
        text.setMaxWidth(Math.round(520 * dp));
        text.setFocusable(false);
        text.setAlpha(0f);
        try {
            text.setTypeface(UiFont.get(context, R.string.font_regular));
        } catch (Exception ignored) {
            // the system font is fine
        }
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.END);
        params.topMargin = Math.round(110 * dp);
        params.setMarginEnd(Math.round(62 * dp));
        root.addView(text, params);
        return text;
    }

    /** The displayed picture's name, faded across a change; a picture without a name hides the caption. */
    private void showCaption(boolean fade) {
        if (caption == null) return;
        String name = names.get(displayed);
        caption.animate().cancel();
        if (name == null) {
            caption.setAlpha(0f);
            return;
        }
        caption.setContentDescription(name);
        if (!fade || caption.getAlpha() == 0f) {
            caption.setText(name);
            caption.setAlpha(1f);
            return;
        }
        caption.animate().alpha(0f).setDuration(250).withEndAction(() -> {
            caption.setText(name);
            caption.animate().alpha(1f).setDuration(350).start();
        }).start();
    }

    /** Names plus sizes: enough to notice a different collection without hashing every image. */
    private static String collectionKey(List<File> images) {
        StringBuilder key = new StringBuilder();
        for (File file : images) key.append(file.getName()).append(':').append(file.length()).append(';');
        return key.toString();
    }

    /** Puts a picture on screen and releases the previous one after a frame has drawn the new one. */
    private void show(Bitmap bitmap) {
        Bitmap old = current;
        current = bitmap;
        // The wallpaper covers the whole root; avoid drawing the fallback colour under it.
        root.setBackground(null);
        image.setImageBitmap(bitmap);
        if (old != null && old != bitmap) image.postDelayed(old::recycle, 500);
    }

    /** Bundled pictures rotate a minute at a time when the set gives us no interval to read. */
    private static final long BUILTIN_INTERVAL_MS = 60_000L;

    private void advanceBuiltin() {
        // A video layer covers the screen; re-decoding a bundled picture would only paint the window opaque
        // over it and cost a few megabytes for something nobody can see.
        if (motionBlocked) return;
        if (builtinAssets.size() < 2) return;
        long changed = preferences.getLong("changed", 0);
        if (!WallpaperRotation.due(changed, System.currentTimeMillis(), BUILTIN_INTERVAL_MS)) return;
        // Walk past any picture that will not decode instead of giving up: one bad JPEG used to leave the set showing
        // the same background for as long as it was on.
        for (int attempt = 0; attempt < builtinAssets.size(); attempt++) {
            builtinIndex = (builtinIndex + 1) % builtinAssets.size();
            Bitmap next = decodeAsset(builtinAssets.get(builtinIndex));
            if (next != null) {
                show(next);
                preferences.edit().putLong("changed", System.currentTimeMillis()).apply();
                return;
            }
        }
    }

    private Bitmap decodeAsset(String name) {
        try (InputStream in = context.getAssets().open("wallpapers/" + name)) {
            BitmapFactory.Options options = new BitmapFactory.Options();
            // Same rule as the pushed collection: half the bytes unless the theme asked for true colour.
            options.inPreferredConfig = bitmapConfig;
            return BitmapFactory.decodeStream(in, null, options);
        } catch (IOException | OutOfMemoryError unreadable) {
            return null;
        }
    }

    private Bitmap decode(File file) {
        try {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(file.getPath(), options);
            int width = options.outWidth, height = options.outHeight;
            if (width <= 0 || height <= 0) return null;
            int sample = WallpaperSize.sampleSize(width, height, this.width, this.height);
            if (!WallpaperSize.accepted(width / sample, height / sample)) return null;
            options.inJustDecodeBounds = false;
            options.inSampleSize = sample;
            int[] scale = WallpaperSize.coverScale(width / sample, height / sample, this.width, this.height);
            if (scale != null) {
                options.inScaled = true;
                options.inDensity = scale[0];
                options.inTargetDensity = scale[1];
            }
            options.inPreferredConfig = bitmapConfig;
            options.inMutable = dimColor != 0;
            Bitmap decoded = BitmapFactory.decodeFile(file.getPath(), options);
            if (decoded == null) return null;
            if (dimColor != 0) new Canvas(decoded).drawColor(dimColor);
            // One copy in GPU memory instead of a software bitmap plus its texture; the decode stays off the UI
            // thread for rotations, and Home's return no longer uploads 4-8 MB to the GPU. Compat.hardwareConfig
            // hands back the software config below API 26, where the HARDWARE constant does not exist - and
            // NoSuchFieldError is an Error, so the catch below would not have saved it.
            Bitmap gpu = decoded.copy(Compat.hardwareConfig(), false);
            if (gpu == null) return decoded;
            decoded.recycle();
            return gpu;
        } catch (Exception | OutOfMemoryError failure) {
            return null;
        }
    }
}
