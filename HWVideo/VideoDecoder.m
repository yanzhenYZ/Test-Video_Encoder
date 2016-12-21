//
//  VideoDecoder.m
//  HWVideo
//
//  Created by yanzhen on 16/8/29.
//  Copyright © 2016年 v2tech. All rights reserved.
//

#import "VideoDecoder.h"
#import <VideoToolbox/VideoToolbox.h>

@implementation VideoDecoder{
    CMVideoFormatDescriptionRef _formatDescription;
    uint8_t* _pps;
    uint8_t* _sps;
    size_t _spsSize;
    size_t _ppsSize;
}
-(void)decodeData:(NSData *)data{
    NSLog(@"TTTT:%@",data);
    uint8_t *frame = (uint8_t *)data.bytes;
    uint32_t frameSize = (uint32_t)data.length;
    int nalu_type = (frame[4] & 0x1F);
    
    //用前4个字节来表示其余全部字节的数量
    uint32_t nalSize = (uint32_t)(frameSize - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    frame[0] = *(pNalSize + 3);
    frame[1] = *(pNalSize + 2);
    frame[2] = *(pNalSize + 1);
    frame[3] = *(pNalSize);
    switch (nalu_type)
    {
            
        case 0x07:
        {
            _spsSize = frameSize - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        }
        case 0x08:
        {
            _ppsSize = frameSize - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        }
        default:
        {
            CMBlockBufferRef blockBuffer = [self createBlockBufferWithData:data];
            CMSampleBufferRef samplebuffer= [self createSampleBufferWithBlockBuffer:blockBuffer];
            [self.delegate didOutputVideoSampleBuffer:samplebuffer];
            
            if (samplebuffer != NULL) {
                CFRelease(samplebuffer);
            }
            if (blockBuffer != NULL) {
                CFRelease(blockBuffer);
            }
            break;
        }
    }
    if (_pps && _sps) {
        [self configureFromatDescription];
    }
}

- (CMBlockBufferRef)createBlockBufferWithData:(NSData*)data
{
    CMBlockBufferRef blockBuffer = NULL;
    
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                          (void*)data.bytes,
                                                          data.length,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          data.length,
                                                          0,
                                                          &blockBuffer);
    assert(status == noErr);
    return blockBuffer;
}

- (CMSampleBufferRef)createSampleBufferWithBlockBuffer:(CMBlockBufferRef)block
{
    CMSampleBufferRef sampleBuffer = NULL;
    if (_formatDescription) {
        OSStatus status = CMSampleBufferCreate(kCFAllocatorDefault,
                                               block,
                                               YES,
                                               NULL,
                                               NULL,
                                               _formatDescription,
                                               1,
                                               0,
                                               NULL,
                                               0,
                                               NULL,
                                               &sampleBuffer);
        
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        assert(status == noErr);
    }
    
    return sampleBuffer;
}

- (void)configureFromatDescription
{
    if (_formatDescription) {
#pragma mark - 111111
        CFRelease(_formatDescription);
        _formatDescription = nil;
//        return;
    }
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize};
    CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                        2,
                                                        parameterSetPointers,
                                                        parameterSetSizes,
                                                        4,
                                                        (CMFormatDescriptionRef*)&_formatDescription);
}


@end
