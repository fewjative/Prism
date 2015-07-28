#import "BeatVisualizerView.h"
#import "MeterTable.h"


static UIColor* colorWithString(NSString * stringToConvert)
{
    NSString *cString = [stringToConvert stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Proper color strings are denoted with braces
    if (![cString hasPrefix:@"{"]) return nil;
    if (![cString hasSuffix:@"}"]) return nil;
    
    // Remove braces    
    cString = [cString substringFromIndex:1];
    cString = [cString substringToIndex:([cString length] - 1)];
    
    // Separate into components by removing commas and spaces
    NSArray *components = [cString componentsSeparatedByString:@", "];
    if ([components count] != 4) return nil;
    
    // Create the color
    return [UIColor colorWithRed:[[components objectAtIndex:0] floatValue]
                           green:[[components objectAtIndex:1] floatValue] 
                            blue:[[components objectAtIndex:2] floatValue]
                           alpha:[[components objectAtIndex:3] floatValue]];
}

@interface BeatVisualizerView ()

@end

@implementation BeatVisualizerView
{
    MeterTable meterTable;
}

+(instancetype)sharedInstance {
    static dispatch_once_t pred;
    static BeatVisualizerView *shared = nil;
     
    dispatch_once(&pred, ^{
        shared = [[BeatVisualizerView alloc] init];
    });
    return shared;
}

- (id)init
{
    if(self = [super init]) {
        [self setup];
    }
    
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self setup];
    }
    
    return self;
}

- (void)awakeFromNib
{
    NSLog(@"[Prism]awakeFromNib");
    [self setup];
}

- (void)setup
{
    NSLog(@"[Prism]Setup started");
    self.primaryColor = [UIColor blackColor];
    self.secondaryColor = [UIColor redColor];
    self.colorFlowPrimary = [UIColor blackColor];
    self.colorFlowSecondary = [UIColor redColor];
    self.prismFlowPrimary = [UIColor blackColor];
    self.prismFlowSecondary = [UIColor redColor];
    self.beatPrimaryColor = [UIColor blackColor];
    self.beatSecondaryColor = [UIColor redColor];
    self.spectrumPrimaryColor = [UIColor redColor];

    self.backgroundColor = [UIColor clearColor];
    self.overlayColor = [UIColor whiteColor];
    self.overlayAlbumArt = 0;
    self.idleAmplitude = 0.01f;
    self.waveThreshold = 25;
    self.priorAmplitude = self.bounds.size.height/2.0;
    self.createWave = false;
    self.waves = [[NSMutableArray alloc] init];
    self.type = 0.0;
    self.outData = nil;
    self.avg = 0.0;
    self.numBars = 30;
    self.sum = 0.0;
    self.bar_width = 0.0;
    self.scaled_avg = 0.0;
    self.mag = 30;
    self.volume = 1;
    self.displayWave = 0;
    self.useColorFlow = NO;
    self.usePrismFlow = NO;
    self.frequency = 1.0f;
    self.amplitude = 1.0f;
    self.numberOfWaves = 5;
    self.phaseShift = -0.15f;
    self.density = 5.0f;
    self.primaryWaveLineWidth = 3.0f;
    self.secondaryWaveLineWidth = 1.0f;
    self.spectrumStyle = 0;
    self.isVisible = NO;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ColorFlowMusicAppColorReversionNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ColorFlowMusicAppColorizationNotification" object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                        selector:@selector(revertUI:)
                                        name:@"ColorFlowMusicAppColorReversionNotification"
                                        object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(colorizeUI:)
                                            name:@"ColorFlowMusicAppColorizationNotification"
                                            object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ColorFlowLockScreenColorReversionNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ColorFlowLockScreenColorizationNotification" object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                        selector:@selector(revertLSUI:)
                                        name:@"ColorFlowLockScreenColorReversionNotification"
                                        object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(colorizeLSUI:)
                                            name:@"ColorFlowLockScreenColorizationNotification"
                                            object:nil];

    NSLog(@"[Prism]Setup ended");
}

-(void)revertUI:(NSNotification*)notification{
    NSLog(@"[Prism]revertUI");

}

-(void)colorizeUI:(NSNotification*)notification{
    NSLog(@"[Prism]colorizeUI");

    NSDictionary * userInfo = [notification userInfo];
    self.colorFlowPrimary = userInfo[@"PrimaryColor"];
    self.colorFlowSecondary = userInfo[@"SecondaryColor"];
}

-(void)revertLSUI:(NSNotification*)notification{
    NSLog(@"[Prism]revertLSUI");

}

-(void)colorizeLSUI:(NSNotification*)notification{
    NSLog(@"[Prism]colorizeLSUI");

    NSDictionary * userInfo = [notification userInfo];
    self.colorFlowPrimary = userInfo[@"PrimaryColor"];
    self.colorFlowSecondary = userInfo[@"SecondaryColor"];
}

-(void)toggleVisibility {
    self.isVisible = !self.isVisible;
}

-(void)updateWithLevel:(CGFloat)level withData:(NSMutableArray*)data withMag:(double)mag withVol:(CGFloat)vol withType:(CGFloat)type
{
    self.phase += self.phaseShift;
    self.volume = vol;
    self.outData = data;
    self.type = type;
    float value = meterTable.ValueAt( 20.0f * log10(level*vol));
    self.siriAmplitude = fmax(value, self.idleAmplitude);
    self.amplitude = self.siriAmplitude * self.bounds.size.height;

    NSMutableIndexSet *discard = [NSMutableIndexSet indexSet];

    for( int i=0; i < self.waves.count; i++)
    {
       CGFloat val = [[self.waves objectAtIndex:i] floatValue]*1.03;

        if(val > self.bounds.size.height)
            [discard addIndex:i];
        else
            [self.waves replaceObjectAtIndex:i withObject: [NSNumber numberWithFloat:val]];
    }

    [self.waves removeObjectsAtIndexes:discard];

    if(self.amplitude > (self.priorAmplitude + self.waveThreshold))
    {
        NSNumber * num = [NSNumber numberWithFloat:self.amplitude/2.0];
        [self.waves addObject:num];
    }

    self.priorAmplitude = self.amplitude;
    [self setColors];
    [self setNeedsDisplay];
}

-(void)setColors {
    if(self.type == 0.0)
    {
        self.primaryColor = self.beatPrimaryColor;
        self.secondaryColor = self.beatSecondaryColor;
    }
    else if(self.type == 1.0)
    {
        self.primaryColor = self.spectrumPrimaryColor;
    }
}

- (void)drawRect:(CGRect)rect
{    
    if(!self.isVisible)
        return;

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextClearRect(context, self.bounds);
    
    if(self.overlayAlbumArt)
        [self.overlayColor set];
    else
        [self.backgroundColor set];

    CGContextFillRect(context, rect);

    context = UIGraphicsGetCurrentContext();

    if(self.type==0.0)
    {
        int num_circles = 8;
        int bin_size = floor([self.outData count]/num_circles);
        CGRect barRect;
        CGFloat minWidth = rect.size.height/4.0;
        for(int i=0; i < num_circles/2; i++)
        {
            self.sum = 0;
            for(int j=0; j < bin_size; j++)
            {
                self.sum += [self.outData[(i * bin_size) + j] floatValue];
            }
            self.avg = self.sum/bin_size;
            self.scaled_avg = (self.avg / self.mag ) * (rect.size.height/1.5) * self.volume;

            if(self.scaled_avg != self.scaled_avg)
            {
                self.scaled_avg = rect.size.height;
            }

            if(self.scaled_avg > (rect.size.height/1.5))
                self.scaled_avg = rect.size.height/1.5;

            CGRect circlePoint = CGRectMake((rect.size.width/2.0)-(self.scaled_avg/2.0), rect.size.height/2.0-(self.scaled_avg/2.0), self.scaled_avg, self.scaled_avg);
            
            if(self.useColorFlow)
            {
                [[self.colorFlowSecondary colorWithAlphaComponent:.4f] setFill];
            }
            else if(self.usePrismFlow)
            {
                [[self.prismFlowSecondary colorWithAlphaComponent:.4f] setFill];
            }
            else
            {
                [[self.secondaryColor colorWithAlphaComponent:.4f] setFill];
            }

            CGContextFillEllipseInRect(context, circlePoint);
        }

        if(self.useColorFlow)
        {
            [self.colorFlowPrimary setFill];
            [self.colorFlowPrimary setStroke];
        }
        else if(self.usePrismFlow)
        {
            [self.prismFlowPrimary setFill];
            [self.prismFlowPrimary setStroke];
        }
        else
        {
            [self.primaryColor setFill];
            [self.primaryColor setStroke];
        }

        CGContextSetLineWidth(context, 2.0);
        
        for( int i=0; i < self.waves.count; i++)
        {
            UIBezierPath *waveCircle = [UIBezierPath bezierPath];
            float radius = [[self.waves objectAtIndex:i] floatValue];
            [waveCircle addArcWithCenter:CGPointMake(rect.size.width / 2, rect.size.height / 2)
                                    radius:radius
                                startAngle:0
                                  endAngle:2 * M_PI
                                 clockwise:YES];
            waveCircle.lineWidth = 4.0;
            [waveCircle stroke];
        }
        /*CGContextSetLineWidth(context, 2.0);

        if(self.useColorFlow)
        {
            [self.colorFlowSecondary setFill];
            [self.colorFlowSecondary setStroke];
        }
        else if(self.usePrismFlow)
        {
            [self.prismFlowSecondary setFill];
            [self.prismFlowSecondary setStroke];
        }
        else
        {
            [self.secondaryColor setFill];
            [self.secondaryColor setStroke];
        }

        CGRect circlePoint = CGRectMake((rect.size.width/2.0)-(self.amplitude/2.0), rect.size.height/2.0-(self.amplitude/2.0), self.amplitude, self.amplitude);
        CGContextFillEllipseInRect(context, circlePoint);
    */
    }
    else if(self.type==1.0)
    {
        int bin_size = floor([self.outData count]/(self.numBars*2));
        CGRect barRect;
        CGFloat centerX = (rect.size.width/2.0);
        CGFloat centerY = (rect.size.height/2.0);

        if(self.useColorFlow)
        {
            [self.colorFlowSecondary setFill];
            [self.colorFlowSecondary setStroke];
        }
        else if(self.usePrismFlow)
        {
            [self.prismFlowSecondary setFill];
            [self.prismFlowSecondary setStroke];
        }
        else
        {
            [self.secondaryColor setFill];
            [self.secondaryColor setStroke];
        }

        if(self.spectrumStyle == 2 || self.spectrumStyle == 3)
        {
            UIBezierPath *waveCircle = [UIBezierPath bezierPath];
            [waveCircle addArcWithCenter:CGPointMake(rect.size.width / 2.0, rect.size.height / 2.0)
                                    radius:rect.size.width/4.0
                                startAngle:0
                                  endAngle:2 * M_PI
                                 clockwise:YES];
            waveCircle.lineWidth = 4.0;
            [waveCircle stroke];
        }

        for(long i=0; i < self.numBars; i++)
        {
            self.sum = 0;
            for(long j=0; j < bin_size; j++)
            {
                self.sum += [self.outData[(i * bin_size) + j] floatValue];
            }
            self.avg = self.sum/bin_size;
            self.bar_width = (rect.size.width/(self.numBars*2))*2.0;
            self.scaled_avg = (self.avg / self.mag ) * rect.size.height * self.volume;

            if(self.scaled_avg != self.scaled_avg)
            {
                self.scaled_avg = rect.size.height;
            }

            if(self.scaled_avg > rect.size.height)
                self.scaled_avg = rect.size.height;

            UIBezierPath * barPath;
            if(self.spectrumStyle == 0)
            {
                barRect = CGRectMake(i*self.bar_width,rect.size.height-self.scaled_avg,self.bar_width, self.scaled_avg);
                barPath = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:0];
            }
            else if(self.spectrumStyle == 1)
            {
                barRect = CGRectMake(i*self.bar_width,rect.size.height/2.0-self.scaled_avg/2.0,self.bar_width, self.scaled_avg);
                barPath = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:0];
            }
            else if(self.spectrumStyle == 2 || self.spectrumStyle == 3)
            {
                if(self.spectrumStyle == 2)
                {
                   barRect = CGRectMake((rect.size.height/2.0)-(self.bar_width),(rect.size.width/4.0) - (self.scaled_avg/4.0),self.bar_width, self.scaled_avg/4.0);
                }
                else
                    barRect = CGRectMake((rect.size.height/2.0)-(self.bar_width),(rect.size.width/4.0) - (self.scaled_avg/4.0),self.bar_width, self.scaled_avg/2.0);

                barPath = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:0];
                CGFloat degrees = 1.0*i*(360.0/self.numBars);
                CGFloat radians = (degrees* M_PI)/ (180.0);
                //CGAffineTransform translate = CGAffineTransformMakeTranslation()
                //CGAffineTransform rot = CGAffineTransformMakeRotation()
                CGAffineTransform transform = CGAffineTransformMake(cos(radians), sin(radians),-sin(radians),cos(radians),centerX-centerX*cos(radians)+centerY*sin(radians),centerY-centerX*sin(radians)-centerY*cos(radians));
                [barPath applyTransform:transform];
            }

            [barPath fill];
        }
    }
    else
    {
        NSLog(@"[Prism]Not a valid type");
    }
}

@end
