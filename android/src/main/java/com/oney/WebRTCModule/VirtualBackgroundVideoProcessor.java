package com.oney.WebRTCModule;

import static android.graphics.Color.argb;
import static android.graphics.PorterDuff.Mode.DST_OVER;
import static android.graphics.PorterDuff.Mode.SRC_IN;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.PorterDuffXfermode;
import android.opengl.GLES20;
import android.opengl.GLUtils;
import android.util.Log;

import androidx.annotation.Nullable;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableMap;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.segmentation.Segmentation;
import com.google.mlkit.vision.segmentation.SegmentationMask;
import com.google.mlkit.vision.segmentation.Segmenter;
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions;

import org.webrtc.SurfaceTextureHelper;
import org.webrtc.TextureBufferImpl;
import org.webrtc.VideoFrame;
import org.webrtc.VideoProcessor;
import org.webrtc.VideoSink;
import org.webrtc.YuvConverter;

import java.net.URL;

public class VirtualBackgroundVideoProcessor implements VideoProcessor {

    private VideoSink target;
    private final SurfaceTextureHelper surfaceTextureHelper;
    final YuvConverter yuvConverter = new YuvConverter();

    private YuvFrame yuvFrame;
    private Bitmap inputFrameBitmap;
    private int frameCounter = 0;

    private boolean vbStatus = false;
    private int width = 1280;
    private int height = 720;
    private String vbBackgroundImageUri = null;
    private int vbFrameSkip = 3;
    private int vbBlurValue = 0;

    final private ReactApplicationContext context;
    public static String Log_Tag = "REACT_NATIVE_WEBRTC_VB";

    Bitmap backgroundImage;
    Bitmap scaled;

    final SelfieSegmenterOptions options =
            new SelfieSegmenterOptions.Builder()
                    .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
                    .build();
    final Segmenter segmenter = Segmentation.getClient(options);

    public VirtualBackgroundVideoProcessor(ReactApplicationContext context, SurfaceTextureHelper surfaceTextureHelper, final ReadableMap videoConstraintsMap) {
        super();

        this.surfaceTextureHelper = surfaceTextureHelper;
        this.context = context;

        if(videoConstraintsMap == null) return;

        this.width = videoConstraintsMap.getInt("width");
        this.height = videoConstraintsMap.getInt("height");

        if(videoConstraintsMap.hasKey("vb"))
        {
            this.vbStatus = videoConstraintsMap.getBoolean(("vb"));
        }

        if(videoConstraintsMap.hasKey("vbBackgroundImage"))
        {
            this.vbBackgroundImageUri = videoConstraintsMap.getString(("vbBackgroundImage"));
        }

        if(videoConstraintsMap.hasKey("vbFrameSkip"))
        {
            this.vbFrameSkip = videoConstraintsMap.getInt("vbFrameSkip");
        }

        if(videoConstraintsMap.hasKey("vbBlurValue"))
        {
            this.vbBlurValue = videoConstraintsMap.getInt("vbBlurValue");
        }

        if(this.vbBackgroundImageUri == null)
        {
            backgroundImage = BitmapFactory.decodeResource(context.getResources(), R.drawable.portrait_background);
            Log.d(Log_Tag,"VB Background Set Defaul Image :"+ this.vbBackgroundImageUri);
        }
        else
        {
            try {
                backgroundImage = BitmapFactory.decodeStream(new URL(this.vbBackgroundImageUri).openStream());
            }
            catch (Exception e)
            {
                backgroundImage = BitmapFactory.decodeResource(context.getResources(), R.drawable.portrait_background);
                Log.d(Log_Tag,"VB Background Image Creation Fail Uri:"+ this.vbBackgroundImageUri);
            }
        }

        scaled = Bitmap.createScaledBitmap(backgroundImage, this.height, this.width, false );
        // Log.d(Log_Tag,"VB Background Image Init Size -> width : "+ this.width + ", height : " + this.height);
    }

    @Override
    public void setSink(@Nullable VideoSink videoSink) {
        target = videoSink;
    }

    @Override
    public void onCapturerStarted(boolean b) {

    }

    @Override
    public void onCapturerStopped() {

    }

    @Override
    public void onFrameCaptured(VideoFrame videoFrame) {

        if(!vbStatus) {
            target.onFrame(videoFrame);
            //Log.d(Log_Tag, "Bypass VB Process");
            return;
        }
        if(frameCounter == 0) {

            // Log.d(Log_Tag, "VB Actual  Width : "+ this.width + " , Height:"+ this.height);
            // Log.d(Log_Tag, "VB VideoFrame Before Process Width : "+ videoFrame.getRotatedWidth() + " , Height:"+ videoFrame.getRotatedHeight());

            yuvFrame = new YuvFrame(videoFrame);
            inputFrameBitmap = yuvFrame.getBitmap();

            //Log.d(Log_Tag, "VB YUV Process Width : "+ inputFrameBitmap.getWidth() + " , Height:"+ inputFrameBitmap.getHeight());

            InputImage image = InputImage.fromBitmap(inputFrameBitmap, 0);
            Task<SegmentationMask> result =
                    segmenter.process(image)
                            .addOnSuccessListener(
                                    new OnSuccessListener<SegmentationMask>() {
                                        @Override
                                        public void onSuccess(SegmentationMask mask) {

                                            mask.getBuffer().rewind();
                                            int[] arr = maskColorsFromByteBuffer(mask);
                                            Bitmap segmentedBitmap = Bitmap.createBitmap(
                                                    arr, mask.getWidth(), mask.getHeight(), Bitmap.Config.ARGB_8888
                                            );
                                            arr = null;

                                            Bitmap segmentedBitmapMutable = segmentedBitmap.copy(Bitmap.Config.ARGB_8888, true);
                                            segmentedBitmap.recycle();
                                            Canvas canvas = new Canvas(segmentedBitmapMutable);

                                            Paint paint = new Paint();
                                            paint.setXfermode(new PorterDuffXfermode(SRC_IN));
                                            Bitmap newBitmap  = vbBlurValue > 0  ? fastBlur(inputFrameBitmap,1, vbBlurValue) :  Bitmap.createScaledBitmap(backgroundImage, mask.getWidth(), mask.getHeight(), false );
                                            canvas.drawBitmap(newBitmap, 0, 0, paint);
                                            paint.setXfermode(new PorterDuffXfermode(DST_OVER));
                                            canvas.drawBitmap(inputFrameBitmap, 0, 0, paint);
                                            surfaceTextureHelper.getHandler().post(new Runnable() {
                                                @Override
                                                public void run() {

                                                    GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
                                                    TextureBufferImpl buffer = new TextureBufferImpl(segmentedBitmapMutable.getWidth(),
                                                            segmentedBitmapMutable.getHeight(), VideoFrame.TextureBuffer.Type.RGB,
                                                            GLES20.GL_TEXTURE0, new Matrix(), surfaceTextureHelper.getHandler(), yuvConverter, null);
                                                    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE0);

                                                    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST);
                                                    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST);
                                                    GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, segmentedBitmapMutable, 0);
                                                    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0);

                                                    VideoFrame.I420Buffer i420Buf = yuvConverter.convert(buffer);
                                                    VideoFrame out = new VideoFrame(i420Buf, 180, videoFrame.getTimestampNs());

                                                    buffer.release();
                                                    //yuvFrame.dispose();
                                                    target.onFrame(out);
                                                    out.release();
                                                }
                                            });

                                        }
                                    });
        }
        updateFrameCounter();
    }

    private void updateFrameCounter() {
        frameCounter++;
        if(frameCounter >= this.vbFrameSkip) {
            frameCounter = 0;
        }
    }

    private int[] maskColorsFromByteBuffer(SegmentationMask mask) {
        int[] colors = new int[mask.getHeight() * mask.getWidth()];
        for (int i = 0; i < mask.getHeight() * mask.getWidth(); i++) {
            float backgroundLikelihood = 1 - mask.getBuffer().getFloat();
            if (backgroundLikelihood > 0.9) {
                colors[i] = argb(255, 255, 0, 255);
            } else if (backgroundLikelihood > 0.2) {
                // Linear interpolation to make sure when backgroundLikelihood is 0.2, the alpha is 0 and
                // when backgroundLikelihood is 0.9, the alpha is 128.
                // +0.5 to round the float value to the nearest int.
                double d = 182.9 * backgroundLikelihood - 36.6 + 0.5;
                int alpha = (int) d;
                colors[i] = argb(alpha, 255, 0, 255);
            }
        }
        return colors;
    }

    private Bitmap fastBlur(Bitmap sentBitmap, float scale, int radius) {

        int width = Math.round(sentBitmap.getWidth() * scale);
        int height = Math.round(sentBitmap.getHeight() * scale);
        sentBitmap = Bitmap.createScaledBitmap(sentBitmap, width, height, false);

        Bitmap bitmap = sentBitmap.copy(sentBitmap.getConfig(), true);

        if (radius < 1) {
            return (null);
        }

        int w = bitmap.getWidth();
        int h = bitmap.getHeight();

        int[] pix = new int[w * h];
        //Log.e("pix", w + " " + h + " " + pix.length);
        bitmap.getPixels(pix, 0, w, 0, 0, w, h);

        int wm = w - 1;
        int hm = h - 1;
        int wh = w * h;
        int div = radius + radius + 1;

        int r[] = new int[wh];
        int g[] = new int[wh];
        int b[] = new int[wh];
        int rsum, gsum, bsum, x, y, i, p, yp, yi, yw;
        int vmin[] = new int[Math.max(w, h)];

        int divsum = (div + 1) >> 1;
        divsum *= divsum;
        int dv[] = new int[256 * divsum];
        for (i = 0; i < 256 * divsum; i++) {
            dv[i] = (i / divsum);
        }

        yw = yi = 0;

        int[][] stack = new int[div][3];
        int stackpointer;
        int stackstart;
        int[] sir;
        int rbs;
        int r1 = radius + 1;
        int routsum, goutsum, boutsum;
        int rinsum, ginsum, binsum;

        for (y = 0; y < h; y++) {
            rinsum = ginsum = binsum = routsum = goutsum = boutsum = rsum = gsum = bsum = 0;
            for (i = -radius; i <= radius; i++) {
                p = pix[yi + Math.min(wm, Math.max(i, 0))];
                sir = stack[i + radius];
                sir[0] = (p & 0xff0000) >> 16;
                sir[1] = (p & 0x00ff00) >> 8;
                sir[2] = (p & 0x0000ff);
                rbs = r1 - Math.abs(i);
                rsum += sir[0] * rbs;
                gsum += sir[1] * rbs;
                bsum += sir[2] * rbs;
                if (i > 0) {
                    rinsum += sir[0];
                    ginsum += sir[1];
                    binsum += sir[2];
                } else {
                    routsum += sir[0];
                    goutsum += sir[1];
                    boutsum += sir[2];
                }
            }
            stackpointer = radius;

            for (x = 0; x < w; x++) {

                r[yi] = dv[rsum];
                g[yi] = dv[gsum];
                b[yi] = dv[bsum];

                rsum -= routsum;
                gsum -= goutsum;
                bsum -= boutsum;

                stackstart = stackpointer - radius + div;
                sir = stack[stackstart % div];

                routsum -= sir[0];
                goutsum -= sir[1];
                boutsum -= sir[2];

                if (y == 0) {
                    vmin[x] = Math.min(x + radius + 1, wm);
                }
                p = pix[yw + vmin[x]];

                sir[0] = (p & 0xff0000) >> 16;
                sir[1] = (p & 0x00ff00) >> 8;
                sir[2] = (p & 0x0000ff);

                rinsum += sir[0];
                ginsum += sir[1];
                binsum += sir[2];

                rsum += rinsum;
                gsum += ginsum;
                bsum += binsum;

                stackpointer = (stackpointer + 1) % div;
                sir = stack[(stackpointer) % div];

                routsum += sir[0];
                goutsum += sir[1];
                boutsum += sir[2];

                rinsum -= sir[0];
                ginsum -= sir[1];
                binsum -= sir[2];

                yi++;
            }
            yw += w;
        }
        for (x = 0; x < w; x++) {
            rinsum = ginsum = binsum = routsum = goutsum = boutsum = rsum = gsum = bsum = 0;
            yp = -radius * w;
            for (i = -radius; i <= radius; i++) {
                yi = Math.max(0, yp) + x;

                sir = stack[i + radius];

                sir[0] = r[yi];
                sir[1] = g[yi];
                sir[2] = b[yi];

                rbs = r1 - Math.abs(i);

                rsum += r[yi] * rbs;
                gsum += g[yi] * rbs;
                bsum += b[yi] * rbs;

                if (i > 0) {
                    rinsum += sir[0];
                    ginsum += sir[1];
                    binsum += sir[2];
                } else {
                    routsum += sir[0];
                    goutsum += sir[1];
                    boutsum += sir[2];
                }

                if (i < hm) {
                    yp += w;
                }
            }
            yi = x;
            stackpointer = radius;
            for (y = 0; y < h; y++) {
                // Preserve alpha channel: ( 0xff000000 & pix[yi] )
                pix[yi] = ( 0xff000000 & pix[yi] ) | ( dv[rsum] << 16 ) | ( dv[gsum] << 8 ) | dv[bsum];

                rsum -= routsum;
                gsum -= goutsum;
                bsum -= boutsum;

                stackstart = stackpointer - radius + div;
                sir = stack[stackstart % div];

                routsum -= sir[0];
                goutsum -= sir[1];
                boutsum -= sir[2];

                if (x == 0) {
                    vmin[y] = Math.min(y + r1, hm) * w;
                }
                p = x + vmin[y];

                sir[0] = r[p];
                sir[1] = g[p];
                sir[2] = b[p];

                rinsum += sir[0];
                ginsum += sir[1];
                binsum += sir[2];

                rsum += rinsum;
                gsum += ginsum;
                bsum += binsum;

                stackpointer = (stackpointer + 1) % div;
                sir = stack[stackpointer];

                routsum += sir[0];
                goutsum += sir[1];
                boutsum += sir[2];

                rinsum -= sir[0];
                ginsum -= sir[1];
                binsum -= sir[2];

                yi += w;
            }
        }

        //Log.e("pix", w + " " + h + " " + pix.length);
        bitmap.setPixels(pix, 0, w, 0, 0, w, h);

        return (bitmap);
    }

    public void  setVbStatus(boolean vbStatus)
    {
        this.vbStatus = vbStatus;
    }
    public void  setWidth(int width)
    {
        this.width = width;
    }
    public void  setHeight(int height)
    {
        this.height = height;
    }
    public void  setSize(int width, int height)
    {
        this.height = height;
        this.width = width;
    }
    public  void setVbImageUri(String uri)
    {
        if(this.vbBackgroundImageUri == null || this.vbBackgroundImageUri.compareTo(uri) != 0 || this.vbBlurValue > 0)
        {
            Bitmap newBackgroundImage = null;
            this.vbBackgroundImageUri = uri;
            try {
                //newBackgroundImage = BitmapFactory.decodeStream(new URL(this.vbBackgroundImageUri).openStream());

                if (uri.startsWith("http://") || uri.startsWith("https://") ||
                        uri.startsWith("file://") || uri.startsWith("asset://") || uri.startsWith("data:")) {
                    newBackgroundImage = BitmapFactory.decodeStream(new URL(this.vbBackgroundImageUri).openStream());
                } else {
                    int drawableId = this.context.getResources()
                            .getIdentifier(uri, "drawable", this.context
                                    .getPackageName());
                    newBackgroundImage = BitmapFactory.decodeResource(this.context.getResources(), drawableId);
                }
            }
            catch (Exception e)
            {
                Log.d(Log_Tag,"VB New Background Image Creation Fail Uri:"+ this.vbBackgroundImageUri);
            }
            finally {
                if(newBackgroundImage != null)
                {
                    this.backgroundImage = newBackgroundImage;
                    this.scaled = Bitmap.createScaledBitmap(backgroundImage, this.height, this.width, false );
                }
                //disable blur background
                if( this.backgroundImage != null) this.vbBlurValue = 0;
            }
        }
    }

    public void setVbFrameSkip(int vbFrameSkip)
    {
        this.vbFrameSkip = vbFrameSkip;
    }

    public void setVBBlurValue(int blurValue)
    {
        this.vbBlurValue = blurValue;
    }
}
