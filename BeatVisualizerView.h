//
//  BeatVisualizerView.h
//  BeatVisualizerView
//
//  Created by Josh Doctors on 2/28/2015.
//  Copyright (c) 2015 Josh Doctors. All rights reserved.
//
#import <Foundation/NSDistributedNotificationCenter.h>
#import <AppSupport/AppSupport.h>
#import "rocketbootstrap.h"

@interface BeatVisualizerView : UIView

-(void)updateWithLevel:(CGFloat)level withData:(NSMutableArray*)data withMag:(double)mag withVol:(CGFloat)vol withType:(CGFloat)type;
+(instancetype)sharedInstance;
-(void)toggleVisibility;

@property (nonatomic, strong) UIColor *primaryColor;
@property (nonatomic, strong) UIColor *secondaryColor;
@property (nonatomic, strong) UIColor *colorFlowPrimary;
@property (nonatomic, strong) UIColor *colorFlowSecondary;
@property (nonatomic, strong) UIColor *prismFlowPrimary;
@property (nonatomic, strong) UIColor *prismFlowSecondary;
@property (nonatomic, strong) UIColor *beatPrimaryColor;
@property (nonatomic, strong) UIColor *beatSecondaryColor;
@property (nonatomic, strong) UIColor *spectrumPrimaryColor;
@property (nonatomic, strong) UIColor *randomColorPrimary;
@property (nonatomic, strong) UIColor *randomColorSecondary;
@property (nonatomic, strong) UIColor *overlayColor;
@property (nonatomic, strong) NSMutableArray *waves;
@property (nonatomic, strong) NSMutableArray *outData;
@property (nonatomic, assign) CGFloat primaryWaveLineWidth;
@property (nonatomic, assign) CGFloat type;
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, assign) BOOL overlayAlbumArt;
@property (nonatomic, assign) NSInteger numBars;
@property (nonatomic, assign) CGFloat barHeight;
@property (nonatomic, assign) double mag;
@property (nonatomic, assign) double sum;
@property (nonatomic, assign) double avg;
@property (nonatomic, assign) double bar_width;
@property (nonatomic, assign) double scaled_avg;
@property (nonatomic, assign) CGFloat secondaryWaveLineWidth;
@property (nonatomic, assign) CGFloat idleAmplitude;
@property (nonatomic, assign) CGFloat frequency;
@property (nonatomic, assign) CGFloat volume;
@property (nonatomic, assign) CGFloat amplitude;
@property (nonatomic, assign) CGFloat siriAmplitude;
@property (nonatomic, assign) CGFloat priorAmplitude;
@property (nonatomic, assign) CGFloat waveThreshold;
@property (nonatomic, assign) BOOL createWave;
@property (nonatomic, assign) CGFloat density;
@property (nonatomic, assign) CGFloat phaseShift;
@property (nonatomic, assign) CGFloat phase;
@property (nonatomic, assign) NSUInteger numberOfWaves;
@property (nonatomic, assign) NSInteger displayWave;
@property (nonatomic, assign) NSInteger spectrumStyle;
@property (nonatomic, assign) BOOL isVisible;
@end
