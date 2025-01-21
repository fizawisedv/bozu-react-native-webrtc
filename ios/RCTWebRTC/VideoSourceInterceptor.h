//
//  VideoSourceInterceptor.h
//  react-native-webrtc
//
//  Created by YAVUZ SELIM CAKIR on 18.06.2022.
//

#import <Foundation/Foundation.h>
#import <WebRTC/RTCVideoSource.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoSourceInterceptor : NSObject<RTCVideoCapturerDelegate>

@property(nonatomic, strong) RTCVideoSource *videoSource;

- (instancetype)initWithVideoSource: (RTCVideoSource*) videoSource andConstraints:(NSDictionary *)constraints;
- (void)changeVbStatus:(BOOL)vbStatus;
- (void)changeVbImageUri:(NSString*)vbImageUri;
- (void)changeVbFrameSkip:(NSInteger)vbFrameSkip;
- (void)changeVbBlurValue:(NSInteger)vbBlurValue;

@end

NS_ASSUME_NONNULL_END
