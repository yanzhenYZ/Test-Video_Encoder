//
//  ViewController.m
//  HWVideo
//
//  Created by yanzhen on 16/8/29.
//  Copyright © 2016年 v2tech. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "VideoEncoder.h"
#import "VideoDecoder.h"

//最大值不能超过60
static int const frameRate = 10;
static CGFloat const SCALE = 2.5;
@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,HWH264EncoderDelegate,HWH264DecoderOutputDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) dispatch_queue_t dataOutputQueue;
@property (nonatomic, strong) AVCaptureVideoDataOutput* dataOutput;
@property (nonatomic, strong) AVCaptureDeviceInput* deviceInput;
@property(nonatomic, copy) NSString *sessionPreset;
@property (weak, nonatomic) IBOutlet UIImageView *videoView;

@property (nonatomic, strong) AVSampleBufferDisplayLayer *videoPlayer;
@property (nonatomic, strong) AVSampleBufferDisplayLayer *showPlayer;
@property (nonatomic, assign) BOOL front;
@property (nonatomic, strong) VideoEncoder *encoder;
@property (nonatomic, strong) VideoDecoder *decoder;
@property (nonatomic, assign) CGSize videoSize;

@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    //AVCaptureSessionPreset352x288
    //AVCaptureSessionPreset640x480
    //AVCaptureSessionPreset1280x720
    //AVCaptureSessionPresetMedium
    //AVCaptureSessionPreset1920x1080 (后摄像头)
    self.sessionPreset = AVCaptureSessionPreset352x288;
    _videoSize = CGSizeMake(480, 640);

    [_videoView.layer addSublayer:self.videoPlayer];
    [_videoView.layer addSublayer:self.showPlayer];
    [self.showPlayer flushAndRemoveImage];
    _front = YES;
    _encoder = [[VideoEncoder alloc] init];
    _encoder.delegate = self;
    _decoder = [[VideoDecoder alloc] init];
    _decoder.delegate = self;
    }

-(void)didEncodedData:(NSData *)data isKeyFrame:(BOOL)isKey{
    const char bytes[] = "\x00\x00\x00\x01";//视频数据的前4个字节时 0x00 0x00 0x00 0x01
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:data];
    [_decoder decodeData:h264Data];
}

-(void)didEncodedSps:(NSData *)sps pps:(NSData *)pps{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    //发sps
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:sps];
    [_decoder decodeData:h264Data];
    
    //发pps
    [h264Data resetBytesInRange:NSMakeRange(0, [h264Data length])];
    [h264Data setLength:0];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:pps];
    [_decoder decodeData:h264Data];
}

#pragma mark - HWH264DecoderOutputDelegate
-(void)didOutputVideoSampleBuffer:(CMSampleBufferRef)sample{
    [self.showPlayer enqueueSampleBuffer:sample];
}

#pragma mark - 暂停采集
- (IBAction)enableVideo:(id)sender {
    if (self.session.isRunning) {
        [self.session stopRunning];
    }else{
        [self.session startRunning];
    }
    
}
#pragma mark - 切换摄像头
- (IBAction)switchCamera:(id)sender {
    [self stop];
    _front = !_front;
    [self start];
}

- (IBAction)startVideo:(id)sender {
    if (self.session.isRunning) {
        return;
    }
    [_encoder startWithSize:_videoSize bitRate:1024 * 1024];
    [self start];
}



- (void)start{
    
    if (self.session.isRunning) {
        return;
    }
    
    self.session.sessionPreset = self.sessionPreset;
    
    AVCaptureDevice* camera = nil;
    camera = [self cameraWithPosition:_front ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
    
    
    NSError* error;
    
    self.deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (error) {
        NSLog(@"error %@",error.description);
    }
    
    if ([self.session canAddInput:self.deviceInput]) {
        [self.session addInput:self.deviceInput];
    }
    
    
    [self.dataOutput setSampleBufferDelegate:self queue:self.dataOutputQueue];
    if ([self.session canAddOutput:self.dataOutput]) {
        [self.session addOutput:self.dataOutput];
        
    }
    
    AVCaptureConnection* con = [self.dataOutput connectionWithMediaType:AVMediaTypeVideo];
    [con setVideoOrientation:(AVCaptureVideoOrientation)[self curOrientation]];
    
    [camera lockForConfiguration:nil];
    camera.activeVideoMinFrameDuration = CMTimeMake(1, frameRate);
    camera.activeVideoMaxFrameDuration = CMTimeMake(1, frameRate + 2);
    [camera unlockForConfiguration];
    
    if ([camera.activeFormat isVideoStabilizationModeSupported:AVCaptureVideoStabilizationModeCinematic]) {
        [con setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeCinematic];
    }else if([camera.activeFormat isVideoStabilizationModeSupported:AVCaptureVideoStabilizationModeAuto]){
        [con setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    [self.session startRunning];
    //切换摄像头时不可调用
//    [_encoder startWithSize:CGSizeMake(288, 352) bitRate:1024 * 512];
    [self.videoPlayer flushAndRemoveImage];
    [self.showPlayer flushAndRemoveImage];
}

- (void)stop{
    if (self.deviceInput) {
        [self.session removeInput:self.deviceInput];
    }
    
    if (self.dataOutput) {
        [self.session removeOutput:self.dataOutput];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.session stopRunning];
}

#pragma mark - 视频数据
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    [self.videoPlayer enqueueSampleBuffer:sampleBuffer];

    [_encoder encode:sampleBuffer];
    
}


- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for ( AVCaptureDevice *device in devices )
        if ( device.position == position )
            return device;
    return nil;
}

- (UIInterfaceOrientation)curOrientation
{
    return [[UIApplication sharedApplication] statusBarOrientation];
}

#pragma  mark - *** notification selector ***
- (void)willResignActive
{
//    [self stop];
//    [_encoder stop];
}

- (void)didBecomeActive
{
    __block ViewController* blockSelf = self;
    dispatch_async(self.dataOutputQueue, ^{
        //本地
        [blockSelf.videoPlayer flushAndRemoveImage];
        
    });
}

#pragma mark - lazy var
-(AVSampleBufferDisplayLayer *)videoPlayer{
    if (!_videoPlayer) {
        _videoPlayer = [AVSampleBufferDisplayLayer layer];
        _videoPlayer.videoGravity = AVLayerVideoGravityResizeAspect;
        _videoPlayer.backgroundColor = [UIColor redColor].CGColor;
        
        //        _videoPlayer.frame = self.videoView.bounds;
        
        _videoPlayer.frame = CGRectMake(0, 0, _videoSize.width/SCALE, _videoSize.height/SCALE);
    }
    return _videoPlayer;
}

-(AVSampleBufferDisplayLayer *)showPlayer{
    if (!_showPlayer) {
        _showPlayer = [AVSampleBufferDisplayLayer layer];
        _showPlayer.videoGravity = AVLayerVideoGravityResizeAspect;
        _showPlayer.backgroundColor = [UIColor redColor].CGColor;
        
        //        _videoPlayer.frame = self.videoView.bounds;
        
        _showPlayer.frame = CGRectMake(200, 0, 180, 320);
    }
    return _showPlayer;
}

-(dispatch_queue_t)dataOutputQueue{
    if (!_dataOutputQueue) {
        _dataOutputQueue = dispatch_queue_create("com.video.queue", 0);
    }
    return _dataOutputQueue;
}

-(AVCaptureSession *)session{
    if (!_session) {
        _session = [[AVCaptureSession alloc] init];
    }
    return _session;
}

- (AVCaptureVideoDataOutput*)dataOutput
{
    if (!_dataOutput) {
        _dataOutput = [[AVCaptureVideoDataOutput alloc] init];
        _dataOutput.videoSettings =  [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    }
    return _dataOutput;
}


@end
