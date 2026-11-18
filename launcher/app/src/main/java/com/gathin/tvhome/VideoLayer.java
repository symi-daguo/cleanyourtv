package com.gathin.tvhome;

import android.content.Context;
import android.content.SharedPreferences;
import android.media.MediaPlayer;
import android.util.Log;
import android.graphics.SurfaceTexture;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Random;

/**
 * A muted landscape video behind Home, from the theme folder's videos/.
 *
 * The keys come from config.xml (video_wallpaper, video_dim, video_rotation_minutes) and a theme's config.json can
 * override them. One video loops; after video_rotation_minutes another one is picked at random. The player is
 * released whenever the layer stops, so the hardware decoder is free the moment an app opens.
 *
 * The clips live in a "videos" folder next to the theme's config.json. A set whose external storage is gone (Hisense
 * VIDAA: /sdcard points at a mount that is not there) has nowhere to push them, so the app's own private folder is
 * used instead - the same pictures and clips then arrive over adb into /data/data/com.gathin.tvhome/files/videos.
 *
 * <p>The layer is a {@link SurfaceView}, not a TextureView, and that choice carries this whole feature on the
 * boards this fork targets. A TextureView hands each decoded frame to the GPU as a texture and HWUI re-renders
 * the window over it; on a Hisense VIDAA (maxim, Android 6.0) that bind fails every few frames with
 * "GLConsumer: bindTextureImage: clearing GL error: 0x500" and the retry stalls the frame - with the video
 * running, the window fell to ~22 frames a second no matter what the clip was encoded at, and 90 of those
 * errors landed in the log in three minutes. A SurfaceView hands the decoder's buffer straight to
 * SurfaceFlinger: the GPU never touches the frames, the window keeps drawing the tiles and the clock at its
 * own pace, and the video runs at whatever the decoder delivers.
 *
 * <p>The price is that a SurfaceView cannot fade: a clip change is a cut, not a crossfade, and there is no
 * first-frame fade-in. On this hardware the cut is the cheaper artefact by far. The TextureView mode keeps the
 * fade, and returns to the GPU path with all that path's costs.
 */
final class VideoLayer implements SurfaceHolder.Callback, TextureView.SurfaceTextureListener {
    private static final String TAG = "TvHome.Video";
    private static final List<String> EXTENSIONS = Arrays.asList(".mp4", ".webm", ".mkv", ".m4v");
    private static final long MAX_BYTES = 400L * 1024 * 1024;
    private static final String PREFS = "video_rotation";

    /** Which kind of surface the decoder renders into; the two exist because boards disagree about which one
     *  works. On a Hisense VIDAA (maxim, Android 6.0) a TextureView's per-frame texture bind fails every few
     *  frames with GL error 0x500 and playback stutters, so the frames go to a SurfaceView whose buffer the
     *  display hardware composites directly. On a Xiaomi box (Amlogic, Android 9) it is the other way round:
     *  MIUI's window is an opaque RGBx surface that hides whatever sits behind a SurfaceView, while the
     *  Amlogic GPU binds its own decoded format through a TextureView without complaint. config.xml's
     *  video_textureview picks, and a theme's config.json can override it per device. */
    private final boolean useTexture;
    private final TextureView texture;
    private final SurfaceView surfaceView;
    /** The surface the player renders into, whichever view provided it. */
    private Surface readySurface;
    private final List<File> files;
    private final long interval;
    private final SharedPreferences prefs;
    private final Random random = new Random();
    private final Runnable rotate = this::rotateNow;
    /** Called once the video is up: the picture underneath can go. */
    private final Runnable onFirstFrame;
    /** Called when every clip has failed: Home must bring the picture back. */
    private final Runnable onExhausted;
    /** Called on a single play failure: the picture comes back until the next frame. */
    private final Runnable onPlaybackFailed;
    private MediaPlayer player;
    private boolean active;
    private int failures;
    private boolean reported;

    /**
     * Adds the layer at {@code index} of {@code root} when the key is on and videos exist; else null.
     *
     * @param key          "video_wallpaper" for Home, "screensaver_video" for the screensaver.
     * @param on           whether that key is on.
     * @param dim          how dark the video is behind the grid, 0 to 90 percent.
     * @param minutes      how long one video stays before another is picked.
     * @param onFirstFrame run once the first frame is on screen.
     * @param onExhausted  run when every clip has failed and the layer has given up.
     */
    static VideoLayer attach(Context ctx, FrameLayout root, int index, String key, boolean on, int dim, int minutes,
                             boolean useTexture, Runnable onFirstFrame, Runnable onExhausted, Runnable onPlaybackFailed) {
        if (!on) return null;
        List<File> files = videos(ctx);
        if (files.isEmpty()) return null;
        return new VideoLayer(ctx, root, index, files, dim, Math.max(1, minutes) * 60_000L, useTexture,
                onFirstFrame, onExhausted, onPlaybackFailed);
    }

    /** The clips: the theme folder's videos/ first, the app's own folder when the theme folder is not there. */
    static List<File> videos(Context ctx) {
        List<File> list = new ArrayList<>();
        collect(ctx.getExternalFilesDir(null), list);
        if (list.isEmpty()) collect(ctx.getFilesDir(), list);
        Collections.sort(list);
        return list;
    }

    private static void collect(File root, List<File> into) {
        if (root == null) return;
        File[] found = new File(root, "videos").listFiles(f -> {
            String n = f.getName().toLowerCase(Locale.ROOT);
            int dot = n.lastIndexOf('.');
            return f.isFile() && f.length() > 0 && f.length() <= MAX_BYTES
                    && dot > 0 && EXTENSIONS.contains(n.substring(dot));
        });
        if (found != null) Collections.addAll(into, found);
    }

    private VideoLayer(Context ctx, FrameLayout root, int index, List<File> files, int dim, long interval,
                       boolean useTexture, Runnable onFirstFrame, Runnable onExhausted, Runnable onPlaybackFailed) {
        this.files = files;
        this.interval = interval;
        this.onFirstFrame = onFirstFrame;
        this.onExhausted = onExhausted;
        this.onPlaybackFailed = onPlaybackFailed;
        this.useTexture = useTexture;
        prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        int at = Math.max(0, Math.min(index, root.getChildCount()));
        FrameLayout.LayoutParams full = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
        if (useTexture) {
            texture = new TextureView(ctx);
            texture.setAlpha(0f);   // faded in on the first rendered frame, so no black flash
            texture.setSurfaceTextureListener(this);
            texture.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
            root.addView(texture, at, full);
            surfaceView = null;
        } else {
            surfaceView = new SurfaceView(ctx);
            surfaceView.getHolder().addCallback(this);
            // The decoder scales into whatever buffer the surface has; leaving it at the screen's size keeps a
            // 16:9 clip pixel-exact on a 16:9 panel, and the holder's own scaling covers the rest.
            surfaceView.setZOrderOnTop(false);
            surfaceView.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
            root.addView(surfaceView, at, full);
            texture = null;
        }
        if (dim > 0) {
            View shade = new View(ctx);
            shade.setBackgroundColor((dim * 255 / 100) << 24);
            shade.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
            root.addView(shade, at + 1, new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        }
    }

    void start() {
        active = true;
        Surface s = readySurface;
        if (s != null && s.isValid()) play();
    }

    /** Releases the decoder; Home calls this in onPause so apps get it straight away. */
    void stop() {
        active = false;
        View host = useTexture ? texture : surfaceView;
        if (host != null) host.removeCallbacks(rotate);
        release();
    }

    void close() {
        stop();
        onSurfaceGone();
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        onSurfaceReady(holder.getSurface());
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        onSurfaceReady(holder.getSurface());
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        onSurfaceGone();
    }

    @Override
    public void onSurfaceTextureAvailable(SurfaceTexture st, int width, int height) {
        onSurfaceReady(new Surface(st));
    }

    @Override
    public void onSurfaceTextureSizeChanged(SurfaceTexture st, int width, int height) {
    }

    @Override
    public boolean onSurfaceTextureDestroyed(SurfaceTexture st) {
        onSurfaceGone();
        return true;
    }

    @Override
    public void onSurfaceTextureUpdated(SurfaceTexture st) {
        // The TextureView is faded out until the first frame lands. Some players report
        // MEDIA_INFO_VIDEO_RENDERING_START and some (the Amlogic one on a Xiaomi box) never do, so the
        // frame's own callback is what the fade and the picture release wait for: it cannot be missed.
        firstFrame();
    }

    /** The first frame is on screen: fade the layer in and let the picture underneath go. */
    private void firstFrame() {
        if (!reported && useTexture && texture != null) texture.animate().alpha(1f).setDuration(900).start();
        reported = true;
        failures = 0;
        // Every time a frame lands - including a retry after a failure - the fallback picture goes
        // back behind the video. On a SurfaceView a visible picture in the window would cover it.
        if (onFirstFrame != null) onFirstFrame.run();
    }

    private void onSurfaceReady(Surface s) {
        readySurface = s;
        play();
    }

    private void onSurfaceGone() {
        release();
        if (readySurface != null) {
            readySurface.release();
            readySurface = null;
        }
    }

    /** The video for now: the saved one until its time is up, then a different random one. */
    private File current() {
        String name = prefs.getString("file", "");
        long changed = prefs.getLong("changed", 0);
        long now = System.currentTimeMillis();
        File saved = null;
        for (File f : files) if (f.getName().equals(name)) saved = f;
        if (saved != null && now - changed >= 0 && now - changed < interval) return saved;
        File next = files.get(random.nextInt(files.size()));
        if (files.size() > 1) while (next.getName().equals(name)) next = files.get(random.nextInt(files.size()));
        prefs.edit().putString("file", next.getName()).putLong("changed", now).apply();
        return next;
    }

    private void play() {
        if (!active || readySurface == null || player != null || files.isEmpty()) return;
        File video = current();
        long left = interval - (System.currentTimeMillis() - prefs.getLong("changed", 0));
        View host = useTexture ? texture : surfaceView;
        host.removeCallbacks(rotate);
        host.postDelayed(rotate, Math.max(1_000L, left));
        MediaPlayer mp = new MediaPlayer();
        player = mp;
        try {
            mp.setDataSource(video.getPath());
            mp.setSurface(readySurface);
            mp.setVolume(0f, 0f);
            mp.setLooping(true);
            mp.setOnInfoListener((p, what, extra) -> {
                // The SurfaceView has no frame callback of its own, so its first frame is known from here -
                // when the player reports it. The TextureView path learns the same thing from
                // onSurfaceTextureUpdated, which some players never reach this event for.
                if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) firstFrame();
                return false;
            });
            mp.setOnErrorListener((p, what, extra) -> {
                // Aerial (the base of HaloTV) learned this on the Hisense VIDAA MTK9652: the decoder
                // fails at times and the same film plays fine when tried again. Dropping a film on the
                // first error leaves the owner with fewer clips every day. Retry the same one, move to
                // the next only after three in a row, and keep the still picture if nothing plays.
                Log.w(TAG, "Cannot play " + video.getName() + " (" + what + "/" + extra + ")");
                retryOrSkip(video);
                return true;
            });
            mp.setOnPreparedListener(MediaPlayer::start);
            mp.prepareAsync();
        } catch (Exception e) {
            Log.w(TAG, "Cannot open " + video.getName(), e);
            retryOrSkip(video);
        }
    }

    /**
     * A failed play is usually transient on the boards this fork targets (see the error listener).
     * The same clip gets up to three tries before it is set aside; a clip set aside comes back at the
     * next rotation instead of being lost for the session. After six tries with nothing playing the
     * layer gives up and Home restores the still picture - no black video plane.
     */
    private void retryOrSkip(File bad) {
        release();
        // The decoder just failed: the video plane may go black until the retry's first frame.
        // Put the picture back for that window (Aerial's issue #1251 on Hisense MTK9652).
        if (onPlaybackFailed != null) onPlaybackFailed.run();
        if (++failures < 3) {
            // Same film, same saved position: a decoder that failed once often plays on the retry.
            prefs.edit().putLong("changed", System.currentTimeMillis() - interval + 2_000L).apply();
            play();
            return;
        }
        // Three in a row on one film: a different one may play. The saved name is cleared so current()
        // picks a new clip; the bad one stays in the list and comes back on a later rotation.
        prefs.edit().putString("file", "").putLong("changed", 0).apply();
        Log.w(TAG, "Three failures on " + bad.getName() + " - rotating to another clip");
        if (failures < 6) play();
        else if (onExhausted != null) onExhausted.run();
    }

    /** The time is up while Home is on screen: the next video, without a fade a SurfaceView cannot do. */
    private void rotateNow() {
        if (!active) return;
        prefs.edit().putLong("changed", 0).apply();
        release();
        play();
    }

    private void release() {
        MediaPlayer mp = player;
        player = null;
        if (mp != null) {
            try {
                mp.reset();
            } catch (Exception ignored) {
            }
            mp.release();
        }
    }
}
