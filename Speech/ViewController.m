//
// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <AVFoundation/AVFoundation.h>

#import "ViewController.h"
#import "AudioController.h"
#import "SpeechRecognitionService.h"
#import "google/cloud/speech/v1beta1/CloudSpeech.pbrpc.h"

#define SAMPLE_RATE 16000.0f

@interface ViewController () <AudioControllerDelegate>
@property (nonatomic, strong) IBOutlet UITextView *textView;
@property (nonatomic, strong) IBOutlet UIView *cameraPreviewView;

@property (nonatomic, strong) NSMutableData *audioData;
@end


@implementation ViewController

NSString *display = @"";
AVCaptureVideoPreviewLayer *_previewLayer;
AVCaptureSession *_captureSession;

- (void)viewDidLoad {
  [super viewDidLoad];
    
    
    //-- Setup Capture Session.
    _captureSession = [[AVCaptureSession alloc] init];
    
    //-- Creata a video device and input from that Device.  Add the input to the capture session.
    AVCaptureDevice * videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if(videoDevice == nil)
        assert(0);
    
    //-- Add the device to the session.
    NSError *error;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice
                                                                        error:&error];
    if(error)
        assert(0);
    
    [_captureSession addInput:input];
    
    //-- Configure the preview layer
    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [_previewLayer setFrame:CGRectMake(0, 0,
                                       self.cameraPreviewView.frame.size.width,
                                       self.cameraPreviewView.frame.size.height)];
    
    //-- Add the layer to the view that should display the camera input
    [self.cameraPreviewView.layer addSublayer:_previewLayer];
    
    //-- Start the camera
    [_captureSession startRunning];
    
  _textView.textAlignment = NSTextAlignmentCenter;

  CGFloat topCorrect = ([_textView bounds].size.height - [_textView contentSize].height);
  topCorrect = (topCorrect <0.0 ? 0.0 : topCorrect);
  _textView.contentOffset = (CGPoint){.x = 0, .y = -topCorrect};
    
  [self recordAudio];
  [AudioController sharedInstance].delegate = self;
}

- (void)recordAudio {
  AVAudioSession *audioSession = [AVAudioSession sharedInstance];
  [audioSession setCategory:AVAudioSessionCategoryRecord error:nil];

  _audioData = [[NSMutableData alloc] init];
  [[AudioController sharedInstance] prepareWithSampleRate:SAMPLE_RATE];
  [[SpeechRecognitionService sharedInstance] setSampleRate:SAMPLE_RATE];
  [[AudioController sharedInstance] start];
}

- (IBAction)stopAudio:(id)sender {
  [[AudioController sharedInstance] stop];
  [[SpeechRecognitionService sharedInstance] stopStreaming];
}

- (void) processSampleData:(NSData *)data
{
  [self.audioData appendData:data];
  NSInteger frameCount = [data length] / 2;
  int16_t *samples = (int16_t *) [data bytes];
  int64_t sum = 0;
  for (int i = 0; i < frameCount; i++) {
    sum += abs(samples[i]);
  }
  NSLog(@"audio %d %d", (int) frameCount, (int) (sum * 1.0 / frameCount));

  // We recommend sending samples in 100ms chunks
  int chunk_size = 0.1 /* seconds/chunk */ * SAMPLE_RATE * 2 /* bytes/sample */ ; /* bytes/chunk */

  if ([self.audioData length] > chunk_size) {
    NSLog(@"SENDING");
    [[SpeechRecognitionService sharedInstance] streamAudioData:self.audioData
                                                withCompletion:^(StreamingRecognizeResponse *response, NSError *error) {
                                                  if (error) {
                                                    NSLog(@"ERROR: %@", error);
                                                    _textView.text = [error localizedDescription];
                                                    [self stopAudio:nil];
                                                  } else if (response) {
                                                    BOOL finished = NO;
                                                    NSLog(@"RESPONSE: %@", response);
                                                    for (StreamingRecognitionResult *result in response.resultsArray) {
                                                      if (result.isFinal) {
                                                        finished = YES;
                                                      }
                                                    }
                                                    StreamingRecognitionResult *result2 = response.resultsArray[0];
                                                    NSString *text = result2.alternativesArray[0].transcript;
                                                    
                                                    if (!([text isEqualToString:@""] || response.endpointerType)) {
                                                        display = text;
                                                    }
                                                    _textView.text = display;
                                                    if (finished) {
                                                      [self stopAudio:nil];
                                                      [self recordAudio];
                                                    }
                                                  }
                                                }
     ];
    self.audioData = [[NSMutableData alloc] init];
  }
}



@end

