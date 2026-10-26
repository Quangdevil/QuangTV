package software.solid.fluttervlcplayer;

import android.content.Context;
import android.graphics.SurfaceTexture;
import android.util.AttributeSet;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import androidx.annotation.NonNull;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.interfaces.IVLCVout;

/** Android owns the hybrid view's surface; Flutter must not consume it as a texture. */
public class VLCTextureView extends TextureView implements TextureView.SurfaceTextureListener,
        View.OnLayoutChangeListener, IVLCVout.OnNewVideoLayoutListener {
    private MediaPlayer mediaPlayer;
    private boolean wasPlaying;
    private volatile int decodedVideoWidth;
    private volatile int decodedVideoHeight;

    public VLCTextureView(Context context) { super(context); init(); }
    public VLCTextureView(Context context, AttributeSet attrs) { super(context, attrs); init(); }
    public VLCTextureView(Context context, AttributeSet attrs, int style) { super(context, attrs, style); init(); }

    private void init() {
        setFocusable(false);
        setSurfaceTextureListener(this);
        addOnLayoutChangeListener(this);
    }

    public int getDecodedVideoWidth() { return decodedVideoWidth; }
    public int getDecodedVideoHeight() { return decodedVideoHeight; }

    public void setMediaPlayer(MediaPlayer player) {
        if (mediaPlayer != null && mediaPlayer != player && mediaPlayer.getVLCVout().areViewsAttached()) {
            mediaPlayer.getVLCVout().detachViews();
        }
        mediaPlayer = player;
        bindSurface();
    }

    private void bindSurface() {
        SurfaceTexture surface = getSurfaceTexture();
        if (mediaPlayer == null || !isAvailable() || surface == null || surface.isReleased()) return;
        IVLCVout output = mediaPlayer.getVLCVout();
        output.setWindowSize(Math.max(1, getWidth()), Math.max(1, getHeight()));
        if (!output.areViewsAttached()) {
            output.setVideoSurface(surface);
            output.attachViews(this);
            mediaPlayer.setVideoTrackEnabled(true);
        }
    }

    public void dispose() {
        setMediaPlayer(null);
        setSurfaceTextureListener(null);
        removeOnLayoutChangeListener(this);
        // TextureView releases its own SurfaceTexture when Android removes the view.
    }

    @Override public void onSurfaceTextureAvailable(@NonNull SurfaceTexture surface, int width, int height) {
        bindSurface();
        if (mediaPlayer != null && wasPlaying) mediaPlayer.play();
        wasPlaying = false;
    }

    @Override public void onSurfaceTextureSizeChanged(@NonNull SurfaceTexture surface, int width, int height) {
        if (mediaPlayer != null) mediaPlayer.getVLCVout().setWindowSize(width, height);
    }

    @Override public boolean onSurfaceTextureDestroyed(@NonNull SurfaceTexture surface) {
        if (mediaPlayer != null) {
            wasPlaying = mediaPlayer.isPlaying();
            if (mediaPlayer.getVLCVout().areViewsAttached()) mediaPlayer.getVLCVout().detachViews();
        }
        return true;
    }

    @Override public void onSurfaceTextureUpdated(@NonNull SurfaceTexture surface) { }

    @Override public void onNewVideoLayout(IVLCVout output, int width, int height,
            int visibleWidth, int visibleHeight, int sarNum, int sarDen) {
        if (width <= 0 || height <= 0) return;
        decodedVideoWidth = visibleWidth > 0 ? visibleWidth : width;
        decodedVideoHeight = visibleHeight > 0 ? visibleHeight : height;
        int w = getWidth(), h = getHeight();
        if (w <= 0 || h <= 0) return;
        float videoAspect = (float) width / height;
        if ((float) w / h < videoAspect) h = (int) (w / videoAspect);
        ViewGroup.LayoutParams params = getLayoutParams();
        if (params != null && params.height != h) {
            params.width = ViewGroup.LayoutParams.MATCH_PARENT;
            params.height = h;
            setLayoutParams(params);
        }
    }

    @Override public void onLayoutChange(View view, int left, int top, int right, int bottom,
            int oldLeft, int oldTop, int oldRight, int oldBottom) {
        if (mediaPlayer != null && right > left && bottom > top) {
            mediaPlayer.getVLCVout().setWindowSize(right - left, bottom - top);
        }
    }
}
