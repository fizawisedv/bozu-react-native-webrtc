//
//  VideoSourceInterceptor.m
//  react-native-webrtc
//
//  Created by YAVUZ SELIM CAKIR on 18.06.2022.
//

#import "VideoSourceInterceptor.h"
#import "RCTUtils.h"
#import <WebRTC/RTCCVPixelBuffer.h>
#import <WebRTC/RTCVideoFrame.h>
#import <WebRTC/RTCNativeI420Buffer.h>
#import <WebRTC/RTCVideoFrameBuffer.h>

#import "../../apple/AllHeaders/MLKitSegmentationSelfie.h"
#import "../../apple/AllHeaders/MLKitSegmentationSelfie.h"
#import "../../apple/AllHeaders/MLKSegmenter.h"
#import "../../apple/AllHeaders/MLKSegmentationMask.h"
#import "../../apple/AllHeaders/MLKVisionImage.h"

NS_ASSUME_NONNULL_BEGIN

@interface VideoSourceInterceptor ()

@property (nonatomic) RTCVideoCapturer *capturer;
@property (nonatomic, strong) MLKSegmenter *segmenter;
@property (nonatomic) RTCVideoRotation rotation;
@property (nonatomic) int64_t timeStampNs;
@property (nonatomic) CVPixelBufferRef backgroundBuffer;
@property (nonatomic) CVPixelBufferRef rightRotatedBackgroundBuffer;
@property (nonatomic) CVPixelBufferRef leftRotatedBackgroundBuffer;
@property (nonatomic) CVPixelBufferRef upsideRotatedBackgroundBuffer;

@property(nonatomic,assign) BOOL vbStatus ;
@property (nonatomic, nullable) NSString *vbBackgroundImageUri;
@property(nonatomic, assign) NSInteger width;
@property(nonatomic, assign) NSInteger height;
@property(nonatomic, assign) NSInteger idelWidth;
@property(nonatomic, assign) NSInteger idelHeight;
@property(nonatomic, assign) NSInteger vbFrameSkip;
@property(nonatomic, assign) NSInteger vbBlurValue;
@property(nonatomic, assign) NSInteger frameCounter;

@end

@implementation VideoSourceInterceptor


NSString * const portraitBackgroundImageUrl = @"https://i.ibb.co/5RMCH5G/portrait.jpg";
NSString * const rightRotatedBackgroundImageUrl = @"https://i.ibb.co/YNsR7St/rotated-Right.jpg";
NSString * const leftRotatedBackgroundImageUrl = @"https://i.ibb.co/cwwSKFn/rotated-Left.jpg";
NSString * const upsideBackgroundImageUrl = @"https://i.ibb.co/mcSJZQk/upside.jpg";

- (instancetype)initWithVideoSource: (RTCVideoSource*) videoSource
                     andConstraints:(NSDictionary *)constraints {
    if (self = [super init]) {
        _videoSource = videoSource;
        
        MLKSelfieSegmenterOptions *options = [[MLKSelfieSegmenterOptions alloc] init];
        options.segmenterMode = MLKSegmenterModeStream;
        options.shouldEnableRawSizeMask = NO;
        
        self.segmenter = [MLKSegmenter segmenterWithOptions:options];
        
        /*Start Init Virtual Background Configuration*/
        
        //VB Status
        /*if(constraints[@"vb"]) {
            NSNumber *vbStatusNumber = constraints[@"vb"];
            self.vbStatus = [vbStatusNumber boolValue];
            
            NSLog(@"VB Value Received %@", self.vbStatus);
        }
        else{
            self.vbStatus = NO;
        }*/
        
        //Video Width
        if(constraints[@"width"])
        {
            self.width = [constraints[@"width"] intValue];
        }
        else{
            self.width = 1280;
        }
        
        //Video Height
        if(constraints[@"height"])
        {
            self.height = [constraints[@"height"] intValue];
        }
        else{
            self.height = 720;
        }
        
        self.idelWidth = 0;
        self.idelHeight = 0;
        
        //VB Frame Skip
        if(constraints[@"vbFrameSkip"])
        {
            self.vbFrameSkip = [constraints[@"vbFrameSkip"] intValue];
        }
        else{
            self.vbFrameSkip = 3;
        }
        
        self.frameCounter = 0;
        
        //VB Image
        if(constraints[@"vbBackgroundImage"])
        {
            self.vbBackgroundImageUri = [constraints[@"vbBackgroundImage"] stringValue];
        }
        else{
            self.vbBackgroundImageUri = nil;
        }
        
        //[self prepareVBImages:portraitBackgroundImageUrl];
        //[self prepareVBImages:@"1"];
    }
    return self;
}

- (void)changeVbStatus:(BOOL)vbStatus {
    self.vbStatus = vbStatus;
}

- (void)changeVbImageUri:(NSString*)vbImageUri {
        
    if(vbImageUri == nil || (!vbImageUri.length)) return;
    
    NSComparisonResult result = [vbImageUri compare: self.vbBackgroundImageUri];
    
    if((result != NSOrderedAscending && result != NSOrderedDescending) && self.vbBlurValue == 0) return;
       
    [self prepareVBImages:vbImageUri];
    
}

- (void)changeVbFrameSkip:(NSInteger)vbFrameSkip {
        
    if(vbFrameSkip < 0) return;
    self.vbFrameSkip = vbFrameSkip;
}

- (void)changeVbBlurValue:(NSInteger)vbBlurValue {
        
    NSLog(@"Recived changeVbBlurValue %i", self.vbBlurValue);
    
    if(vbBlurValue < 0) return;
    self.vbBlurValue = vbBlurValue;
}

- (void)updateFrameCounter {
    self.frameCounter++;
    if(self.frameCounter >= self.vbFrameSkip) self.frameCounter = 0;
}



- (void) prepareVBImages:(NSString *) imageURL
{
    
    CGSize newSize = (self.idelWidth == 0 || self.idelHeight == 0) ?
    CGSizeMake(self.width, self.height) :
    CGSizeMake(self.idelWidth, self.idelHeight);
    
    NSURL *url = [NSURL URLWithString:imageURL];
    
    UIImage *scaledImage = [self downloadAndRescaleImageWithURL:url toSize:newSize];
    
    if(scaledImage == nil)
    {
        self.vbBackgroundImageUri = nil;
        NSLog(@"Provided Image %@ not scaled", imageURL);
        return;
    }
    
    self.vbBackgroundImageUri = imageURL;
    
    //if Image Url Change to set blur value 0
    if(self.vbBackgroundImageUri != nil || self.vbBackgroundImageUri.length != 0) self.vbBlurValue = 0;
    
    _backgroundBuffer = [self pixelBufferFromUIImage:scaledImage];
    /*_rightRotatedBackgroundBuffer = _backgroundBuffer;
    _leftRotatedBackgroundBuffer = _backgroundBuffer;
    _upsideRotatedBackgroundBuffer = _backgroundBuffer;*/
}

- (CVPixelBufferRef)pixelBufferFromUIImage:(UIImage *)image {

    // Get the image size and create a dictionary of pixel buffer attributes
    CGSize imageSize = image.size;
    NSDictionary *options = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferWidthKey : @(imageSize.width),
        (NSString*)kCVPixelBufferHeightKey : @(imageSize.height),
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32ARGB)
    };
    
    // Create a new pixel buffer with the specified attributes
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, imageSize.width, imageSize.height,
                                          kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)options, &pixelBuffer);
    NSParameterAssert(status == kCVReturnSuccess && pixelBuffer != NULL);
    
    // Lock the pixel buffer base address
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    // Create a bitmap context for the pixel buffer
    void *pxdata = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, imageSize.width, imageSize.height, 8, CVPixelBufferGetBytesPerRow(pixelBuffer),
                                                 rgbColorSpace, kCGImageAlphaPremultipliedLast);
    NSParameterAssert(context);
    
    
    // Draw the image into the bitmap context
    CGContextDrawImage(context, CGRectMake(0, 0, imageSize.width, imageSize.height), image.CGImage);
    
    // Clean up the bitmap context and color space
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    // Unlock the pixel buffer base address
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    // Return the pixel buffer
    return pixelBuffer;
}

- (UIImage *)downloadAndRescaleImageWithURL:(NSURL *)url toSize:(CGSize)newSize {
    
    UIImage *tmpImage = nil;
    
    NSURL *URL = url;
    NSString *scheme = URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"file"]) {
        tmpImage = RCTImageFromLocalAssetURL(URL);
      if (!tmpImage) {
          tmpImage = RCTImageFromLocalBundleAssetURL(URL);
      }
      if (!tmpImage) {
          return nil;
      }
    } else if ([scheme isEqualToString:@"data"]) {
        tmpImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:URL]];
    } else if ([scheme isEqualToString:@"http"]) {
        tmpImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:URL]];
    } else {
        NSString *urlString = [URL absoluteString];
        tmpImage = [UIImage imageNamed:urlString];
    }
    
    // If the image was not downloaded successfully, return nil
    if (!tmpImage) {
        return nil;
    }
    // NSLog(@"Image orientation=============================== %ld", tmpImage.imageOrientation);
    UIImage *image =  [UIImage imageWithCGImage:tmpImage.CGImage scale:tmpImage.scale orientation:tmpImage.imageOrientation == 0 ? UIImageOrientationLeftMirrored : tmpImage.imageOrientation == 3 ? UIImageOrientationDownMirrored : tmpImage.imageOrientation];
    // NSLog(@"New Image orientation=============================== %ld", image.imageOrientation);
    
    
    // Create a new bitmap context with the desired size
    UIGraphicsBeginImageContextWithOptions(newSize, YES  , 0.0);
    
    // Draw the image into the context
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    
    // Get the new scaled image from the context
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    
    // Clean up the bitmap context
    UIGraphicsEndImageContext();
    
    // Return the scaled image
    return scaledImage;
}
- (CVPixelBufferRef) pixelBufferFromImageUrl: (NSString *) imageURL
{
    NSURL *url = [NSURL URLWithString:imageURL];
    CGDataProviderRef dataProvider = CGDataProviderCreateWithURL((CFURLRef)url);
    CGImageRef backgroundRef = CGImageCreateWithJPEGDataProvider(dataProvider, NULL, true, kCGRenderingIntentDefault);

    CVPixelBufferRef resultBuffer = NULL;
    resultBuffer = [self pixelBufferFromCGImage:backgroundRef];

    CGDataProviderRelease(dataProvider);

    return resultBuffer;
}


- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image
{
    NSDictionary *options = @{
                              (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
                              (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                              };

    CVPixelBufferRef pxbuffer = NULL;
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, self.width,
                        self.height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef) options,
                        &pxbuffer);

    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);

    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);

    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(pxdata, self.width,
                                                 self.height, 8, 4*self.width, rgbColorSpace,
                                                 kCGImageAlphaPremultipliedLast);
    NSParameterAssert(context);
    
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(-90 * M_PI / 180.0));
    CGContextTranslateCTM(context, -self.width, 0);
    CGAffineTransform flipVertical = CGAffineTransformMake( 1, 0, 0, -1, 0, self.height );
    CGContextConcatCTM(context, flipVertical);

    CGContextDrawImage(context, CGRectMake(0, 0, self.width,
                                           self.height), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);

    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

- (void)capturer:(nonnull RTCVideoCapturer *)capturer didCaptureVideoFrame:(nonnull RTCVideoFrame *)frame {
    
    self.rotation = frame.rotation;
    self.timeStampNs = frame.timeStampNs;
    self.capturer = capturer;
    
    RTCCVPixelBuffer* pixelBufferr = (RTCCVPixelBuffer *)frame.buffer;
    CVPixelBufferRef pixelBufferRef = pixelBufferr.pixelBuffer;
    
    if((self.idelWidth == 0 || self.idelHeight == 0) && frame.buffer != nil)
    {
        self.idelWidth = frame.width;
        self.idelHeight = frame.height;
    }
    
    /** VB Disable to without process frame return*/
    if(self.vbStatus == NO || ((self.vbBackgroundImageUri == nil ||
                                self.vbBackgroundImageUri.length == 0 || self.backgroundBuffer == nil ) && self.vbBlurValue == 0) || CVPixelBufferGetPixelFormatType(pixelBufferRef) != kCVPixelFormatType_32BGRA)
    {
    
        RTC_OBJC_TYPE(RTCCVPixelBuffer) *rtcPixelBuffer =
              [[RTC_OBJC_TYPE(RTCCVPixelBuffer) alloc] initWithPixelBuffer:pixelBufferRef];
        
        RTCI420Buffer *i420buffer = [rtcPixelBuffer toI420];
        
        RTC_OBJC_TYPE(RTCVideoFrame) *processedFrame =
              [[RTC_OBJC_TYPE(RTCVideoFrame) alloc] initWithBuffer:i420buffer
                                                          rotation:self.rotation
                                                       timeStampNs:self.timeStampNs];
        
        [_videoSource capturer:self.capturer didCaptureVideoFrame:processedFrame];
        
        //NSLog(@"Virtual Background Disabled");
        return;
    }
    
    //NSLog(@"Segmantation Process Applay width:%i , height:%i", self.width, self.height);
    if(self.frameCounter == 0)
    {
        CMSampleBufferRef sampleBuffer = [self getCMSampleBuffer:pixelBufferRef timeStamp:self.timeStampNs];
    
        MLKVisionImage *image = [[MLKVisionImage alloc] initWithBuffer:sampleBuffer];
        image.orientation = [self imageOrientation];
    
//        NSError *error;
//        MLKSegmentationMask *mask =
//            [self.segmenter resultsInImage:image error:&error];
//        if (error != nil) {
//            // Error.
//            return;
//        }
    
        [self.segmenter processImage:image
                     completion:^(MLKSegmentationMask * _Nullable mask,
                                  NSError * _Nullable error) {
                       if (error != nil) {
                         // Error.
                           NSLog(@"processImage error %@", error);
                         return;
                       }
                       // Success. Get a segmentation mask here.
            
            [self applySegmentationMask:mask
                          toPixelBuffer:pixelBufferRef
                               rotation:self.rotation];
            
            RTC_OBJC_TYPE(RTCCVPixelBuffer) *rtcPixelBuffer =
            [[RTC_OBJC_TYPE(RTCCVPixelBuffer) alloc] initWithPixelBuffer:pixelBufferRef];
            
            RTCI420Buffer *i420buffer = [rtcPixelBuffer toI420];
            
            RTC_OBJC_TYPE(RTCVideoFrame) *processedFrame =
            [[RTC_OBJC_TYPE(RTCVideoFrame) alloc] initWithBuffer:i420buffer
                                                        rotation:self.rotation
                                                     timeStampNs:self.timeStampNs];
            
            [_videoSource capturer:self.capturer didCaptureVideoFrame:processedFrame];
            
            CMSampleBufferInvalidate(sampleBuffer);
            CFRelease(sampleBuffer);
            //sampleBuffer = NULL;
            
                     }];
        
//        [self applySegmentationMask:mask
//                      toPixelBuffer:pixelBufferRef
//                           rotation:self.rotation];
//
//        RTC_OBJC_TYPE(RTCCVPixelBuffer) *rtcPixelBuffer =
//        [[RTC_OBJC_TYPE(RTCCVPixelBuffer) alloc] initWithPixelBuffer:pixelBufferRef];
//
//        RTCI420Buffer *i420buffer = [rtcPixelBuffer toI420];
//
//        RTC_OBJC_TYPE(RTCVideoFrame) *processedFrame =
//        [[RTC_OBJC_TYPE(RTCVideoFrame) alloc] initWithBuffer:i420buffer
//                                                    rotation:self.rotation
//                                                 timeStampNs:self.timeStampNs];
//
//        [_videoSource capturer:self.capturer didCaptureVideoFrame:processedFrame];
//
//        CMSampleBufferInvalidate(sampleBuffer);
//        CFRelease(sampleBuffer);
//        sampleBuffer = NULL;
    }
    
    [self updateFrameCounter];
}

- (CMSampleBufferRef)getCMSampleBuffer: (CVPixelBufferRef)pixelBuffer timeStamp: (int64_t) timeStampNs  {

    CMSampleTimingInfo info = kCMTimingInfoInvalid;
    info.presentationTimeStamp = CMTimeMake(timeStampNs, 1000000000);;
    info.duration = kCMTimeInvalid;
    info.decodeTimeStamp = kCMTimeInvalid;

    CMFormatDescriptionRef formatDesc = nil;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);

    CMSampleBufferRef sampleBuffer = nil;

    CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                             pixelBuffer,
                                             formatDesc,
                                             &info,
                                             &sampleBuffer);
    return sampleBuffer;
}

- (UIImageOrientation)imageOrientation {
  return [self imageOrientationFromDevicePosition:AVCaptureDevicePositionFront];
}

- (UIImageOrientation)imageOrientationFromDevicePosition:(AVCaptureDevicePosition)devicePosition {
    
    UIDeviceOrientation deviceOrientation = UIDevice.currentDevice.orientation;
    
    if (deviceOrientation == UIDeviceOrientationFaceDown ||
      deviceOrientation == UIDeviceOrientationFaceUp ||
      deviceOrientation == UIDeviceOrientationUnknown) {
        deviceOrientation = [self currentUIOrientation];
    }
    
    switch (deviceOrientation) {
        case UIDeviceOrientationPortrait:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationLeftMirrored
                                                            : UIImageOrientationRight;
        case UIDeviceOrientationLandscapeLeft:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationDownMirrored
                                                            : UIImageOrientationUp;
        case UIDeviceOrientationPortraitUpsideDown:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationRightMirrored
                                                            : UIImageOrientationLeft;
        case UIDeviceOrientationLandscapeRight:
            return devicePosition == AVCaptureDevicePositionFront ? UIImageOrientationUpMirrored
                                                            : UIImageOrientationDown;
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationUnknown:
            return UIImageOrientationUp;
    }
}

- (UIDeviceOrientation)currentUIOrientation {
  UIDeviceOrientation (^deviceOrientation)(void) = ^UIDeviceOrientation(void) {
      switch (UIApplication.sharedApplication.statusBarOrientation) {
          case UIInterfaceOrientationLandscapeLeft:
              return UIDeviceOrientationLandscapeRight;
          case UIInterfaceOrientationLandscapeRight:
              return UIDeviceOrientationLandscapeLeft;
          case UIInterfaceOrientationPortraitUpsideDown:
              return UIDeviceOrientationPortraitUpsideDown;
          case UIInterfaceOrientationPortrait:
          case UIInterfaceOrientationUnknown:
              return UIDeviceOrientationPortrait;
      }
  };

  if (NSThread.isMainThread) {
      return deviceOrientation();
  } else {
      __block UIDeviceOrientation currentOrientation = UIDeviceOrientationPortrait;
      dispatch_sync(dispatch_get_main_queue(), ^{
      currentOrientation = deviceOrientation();
      });
    return currentOrientation;
  }
}

- (void)applySegmentationMask:(MLKSegmentationMask *)mask
                toPixelBuffer:(CVPixelBufferRef)imageBuffer
                     rotation:(RTCVideoRotation)rotation{
    
    CVPixelBufferRef currentBackground = NULL;
    CVPixelBufferRef blurBackground = NULL;
    
    BOOL isBlur  = self.vbBlurValue > 0 ? YES : NO ;
    
    if(isBlur)
    {
        blurBackground = [self blurImageEffect:imageBuffer withRadius:self.vbBlurValue];
    }
    else
    {
        currentBackground = _backgroundBuffer;
    }
    
    
    /*NSLog(@"Mask (%i, %i),  Frame (%i,%i), Image (%i,%i), Idel (%i,%i)", CVPixelBufferGetWidth(mask.buffer), CVPixelBufferGetHeight(mask.buffer),
          CVPixelBufferGetWidth(imageBuffer), CVPixelBufferGetHeight(imageBuffer), CVPixelBufferGetWidth(currentBackground),
           CVPixelBufferGetHeight(currentBackground), self.idelWidth, self.idelHeight);*/
    
   /* switch (rotation) {
        case RTCVideoRotation_90:
            currentBackground = _backgroundBuffer;
            break;
        case RTCVideoRotation_0: //Right rotated screen
            currentBackground = _leftRotatedBackgroundBuffer;
            break;
        case RTCVideoRotation_270: //Upside down screen
            currentBackground = _upsideRotatedBackgroundBuffer;
            break;
        case RTCVideoRotation_180: //Left rotated screen
            currentBackground = _rightRotatedBackgroundBuffer;
            break;
    }*/
    
    size_t width = CVPixelBufferGetWidth(mask.buffer);
    size_t height = CVPixelBufferGetHeight(mask.buffer);

    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    CVPixelBufferLockBaseAddress(isBlur ? blurBackground : currentBackground, 0);
    CVPixelBufferLockBaseAddress(mask.buffer, kCVPixelBufferLock_ReadOnly);

    float *maskAddress = (float *)CVPixelBufferGetBaseAddress(mask.buffer);
    size_t maskBytesPerRow = CVPixelBufferGetBytesPerRow(mask.buffer);

    unsigned char *imageAddress = (unsigned char *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    static const int kBGRABytesPerPixel = 4;
    
    unsigned char *backgroundImageAddress = (unsigned char *)CVPixelBufferGetBaseAddress(isBlur ? blurBackground : currentBackground);
    size_t backgroundImageBytesPerRow = CVPixelBufferGetBytesPerRow(isBlur ? blurBackground : currentBackground);
     
    static const float kMaxColorComponentValue = 255.0f;

    for (int row = 0; row < height; ++row) {
        for (int col = 0; col < width; ++col) {
            int pixelOffset = col * kBGRABytesPerPixel;
            int blueOffset = pixelOffset;
            int greenOffset = pixelOffset + 1;
            int redOffset = pixelOffset + 2;
            int alphaOffset = pixelOffset + 3;

            float maskValue = maskAddress[col];
            float backgroundRegionRatio = 1.0f - maskValue;

            float originalPixelRed = imageAddress[redOffset] / kMaxColorComponentValue;
            float originalPixelGreen = imageAddress[greenOffset] / kMaxColorComponentValue;
            float originalPixelBlue = imageAddress[blueOffset] / kMaxColorComponentValue;
            float originalPixelAlpha = imageAddress[alphaOffset] / kMaxColorComponentValue;
        
            float redOverlay = backgroundImageAddress[blueOffset] / kMaxColorComponentValue;
            float greenOverlay = backgroundImageAddress[greenOffset] / kMaxColorComponentValue;
            float blueOverlay = backgroundImageAddress[redOffset] / kMaxColorComponentValue;
            float alphaOverlay = backgroundRegionRatio;

            // Calculate composite color component values.
            // Derived from https://en.wikipedia.org/wiki/Alpha_compositing#Alpha_blending
            float compositeAlpha = ((1.0f - alphaOverlay) * originalPixelAlpha) + alphaOverlay;
            float compositeRed = 0.0f;
            float compositeGreen = 0.0f;
            float compositeBlue = 0.0f;
            // Only perform rgb blending calculations if the output alpha is > 0. A zero-value alpha
            // means none of the color channels actually matter, and would introduce division by 0.
            if (fabs(compositeAlpha) > FLT_EPSILON) {
                compositeRed = (((1.0f - alphaOverlay) * originalPixelAlpha * originalPixelRed) +
                        (alphaOverlay * redOverlay)) /
                       compositeAlpha;
                compositeGreen = (((1.0f - alphaOverlay) * originalPixelAlpha * originalPixelGreen) +
                          (alphaOverlay * greenOverlay)) /
                         compositeAlpha;
                compositeBlue = (((1.0f - alphaOverlay) * originalPixelAlpha * originalPixelBlue) +
                         (alphaOverlay * blueOverlay)) /
                        compositeAlpha;
            }

            imageAddress[blueOffset] = compositeBlue * kMaxColorComponentValue;
            imageAddress[greenOffset] = compositeGreen * kMaxColorComponentValue;
            imageAddress[redOffset] = compositeRed * kMaxColorComponentValue;
            imageAddress[alphaOffset] = compositeAlpha * kMaxColorComponentValue;
        }
        imageAddress += bytesPerRow / sizeof(unsigned char);
        backgroundImageAddress += backgroundImageBytesPerRow / sizeof(unsigned char);
        maskAddress += maskBytesPerRow / sizeof(float);
    }

    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    CVPixelBufferUnlockBaseAddress(isBlur ? blurBackground : currentBackground, 0);
    CVPixelBufferUnlockBaseAddress(mask.buffer, kCVPixelBufferLock_ReadOnly);
    
    if(blurBackground != NULL && isBlur)
    {
        CVPixelBufferRelease(blurBackground);
    }
}

/**Blur Effect*/
- (UIImage *)imageFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return image;
}


- (UIImage *)blurredImageWithImage:(UIImage *)sourceImage blurRadius:(CGFloat) blurRadius
{

    //  Create our blurred image
    CIContext *context = [CIContext contextWithOptions:nil];
    CIImage *inputImage = [CIImage imageWithCGImage:sourceImage.CGImage];

    //  Setting up Gaussian Blur
    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [filter setValue:inputImage forKey:kCIInputImageKey];
    [filter setValue:[NSNumber numberWithFloat:blurRadius] forKey:@"inputRadius"];
    CIImage *result = [filter valueForKey:kCIOutputImageKey];

    /*  CIGaussianBlur has a tendency to shrink the image a little, this ensures it matches
     *  up exactly to the bounds of our original image */
    CGImageRef cgImage = [context createCGImage:result fromRect:[inputImage extent]];

    UIImage *retVal = [UIImage imageWithCGImage:cgImage];

    if (cgImage) {
        CGImageRelease(cgImage);
    }

    return retVal;
}
-(CVPixelBufferRef)blurImageEffect:(CVPixelBufferRef )imageBuffRef withRadius:(CGFloat)radius
{
    UIImage *imgage = [self imageFromPixelBuffer:imageBuffRef];
    UIImage *blurImgage = [self blurredImageWithImage:imgage blurRadius:radius];
    return [self pixelBufferFromUIImage:blurImgage];
}

@end

NS_ASSUME_NONNULL_END

