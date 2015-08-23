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
    NSLog(@"[Prism]Visualizer setup started.");
    self.primaryColor = [UIColor cyanColor];
    self.secondaryColor = [UIColor magentaColor];
    self.colorFlowPrimary = [UIColor blackColor];
    self.colorFlowSecondary = [UIColor redColor];
    self.prismFlowPrimary = [UIColor blackColor];
    self.prismFlowSecondary = [UIColor redColor];
    self.beatPrimaryColor = [UIColor cyanColor];
    self.beatSecondaryColor = [UIColor magentaColor];
    self.spectrumPrimaryColor = [UIColor cyanColor];
    self.randomColorPrimary = [UIColor cyanColor];
    self.randomColorSecondary = [UIColor magentaColor];

    self.backgroundColor = [UIColor clearColor];
    self.overlayColor = [UIColor whiteColor];
    self.overlayAlbumArt = 0;
    self.idleAmplitude = 0.01f;
    self.waveThreshold = 25;
    self.priorAmplitude = self.bounds.size.height/2.0;
    self.createWave = false;
    self.waves = [[NSMutableArray alloc] init];
    self.type = 0.0;
    self.outData = [NSMutableArray arrayWithCapacity:2];
    self.avg = 0.0;
    self.numBars = 30;
    self.barHeight = 1.0;
    self.sum = 0.0;
    self.bar_width = 0.0;
    self.scaled_avg = 0.0;
    self.mag = 30;
    self.volume = 1;
    self.displayWave = 0;
    self.colorStyle = 0;
    self.frequency = 1.0f;
    self.amplitude = 1.0f;
    self.numberOfWaves = 5;
    self.density = 5.0f;
    self.primaryWaveLineWidth = 3.0f;
    self.secondaryWaveLineWidth = 1.0f;
    self.spectrumStyle = 0;
    self.isVisible = NO;
    self.outDataLength = 1024;
    self.level = 0.0;

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(processAndDisplay)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

    /*self.waveformLayer = [AudioPlotWaveformLayer layer];
    self.waveformLayer.frame = self.bounds;
    self.waveformLayer.lineWidth = 1.0f;
    self.waveformLayer.fillColor = [[UIColor clearColor] CGColor];
    self.waveformLayer.backgroundColor = [[UIColor clearColor] CGColor];
    self.waveformLayer.strokeColor = [[UIColor cyanColor] CGColor];
    self.waveformLayer.opaque = YES;

    [self.layer insertSublayer:self.waveformLayer atIndex:0];*/
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"GeneratedPrismColors" object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                        selector:@selector(generatedPrismColors:)
                                        name:@"GeneratedPrismColors"
                                        object:nil];

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

    //self.points = (CGPoint*)calloc(8192, sizeof(CGPoint));
    //self.pointCount = 100;
    NSLog(@"[Prism]Visualizer setup ended.");
}

-(void)validateDisplayLink {

    if(self.displayLink.duration ==  0)
    {
        [self.displayLink invalidate];
        self.displayLink = nil;

        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(processAndDisplay)];
        [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
}

-(void)dealloc {
    NSLog(@"[Prism]BeatVisualizerView dealloc");
    [self.displayLink invalidate];
    self.displayLink = nil;
}

-(void)generatedPrismColors:(NSNotification*)notification{
    NSLog(@"[Prism]GeneratedPrismColors BeatVisualizerView");
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

/*- (void)layoutSubviews
{
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.waveformLayer.frame = self.bounds;
    if(self.type == self.type)
        [self redraw];
    [CATransaction commit];
}

-(void)pause {

    [UIView animateWithDuration:.4
        animations:^{
            self.alpha = 0;
        }];
}

-(void)play {
    [UIView animateWithDuration:.4
                animations:^{
                    self.alpha = self.transparency;
        }];
}*/

-(void)updateWithLevel:(CGFloat)level withData:(NSMutableArray*)data withLength:(NSInteger)length withVol:(CGFloat)vol withType:(CGFloat)type
{
    self.volume = vol;
    self.outDataLength = length;
    self.type = type;
    self.level = level;
    
    @synchronized(self)
    {
        if(self.outData.count > 2)
        {
            [self.outData removeObjectAtIndex:0];
        }

        if(data)
        {
            [self.outData addObject:data];
        }
    }

    [self validateDisplayLink];
}

-(void)processAndDisplay {

    if(self.type == 0)
    {
        float value = meterTable.ValueAt( 20.0f * log10(self.level*self.volume));
        self.siriAmplitude = fmax(value, self.idleAmplitude);
        self.amplitude = self.siriAmplitude * self.bounds.size.height;

        NSMutableIndexSet *discard = [NSMutableIndexSet indexSet];

        for( int i=0; i < self.waves.count; i++)
        {
           CGFloat val = [[self.waves objectAtIndex:i] floatValue]*1.02;

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
    }
    
    [self setColors];

    /*if(2 == 2.0 )
    {
        [self adjustData];
        [self redraw];
        return;
    }*/
    //self.type = 3.0;
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
        self.secondaryColor = self.spectrumPrimaryColor;
    }
}

- (void)drawRect:(CGRect)rect
{   
    NSArray * currentSpectrumData = nil;

    @synchronized(self)
    {
        if(self.outData.count > 0)
        {
            currentSpectrumData = [[self.outData objectAtIndex:0] copy];
        }

        if(self.outData.count > 1)
        {
            [self.outData removeObjectAtIndex:0];
        }
    }

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
        int bin_size = floor(self.outDataLength/num_circles);

        for(int i=0; i < num_circles/2; i++)
        {
            self.sum = 0;
            for(int j=0; j < bin_size; j++)
            {
                self.sum += [[currentSpectrumData objectAtIndex:((i * bin_size) + j)] floatValue];
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
            
            if( self.colorStyle == 0)
            {
                [[self.secondaryColor colorWithAlphaComponent:.4f] setFill];
            }
            else if(self.colorStyle == 1)
            {
                [[self.colorFlowSecondary colorWithAlphaComponent:.4f] setFill];
            }
            else if(self.colorStyle == 2)
            {
                [[self.prismFlowSecondary colorWithAlphaComponent:.4f] setFill];
            }
            else if(self.colorStyle == 3)
            {
                [[self.randomColorSecondary colorWithAlphaComponent:.4f] setFill];
            }

            CGContextFillEllipseInRect(context, circlePoint);
        }

        if(self.colorStyle == 0)
        {
            [self.primaryColor setFill];
            [self.primaryColor setStroke];
        }
        else if(self.colorStyle == 1)
        {
            [self.colorFlowPrimary setFill];
            [self.colorFlowPrimary setStroke];
        }
        else if(self.colorStyle == 2)
        {
            [self.prismFlowPrimary setFill];
            [self.prismFlowPrimary setStroke];
        }
        else if(self.colorStyle == 3)
        {
            [self.randomColorPrimary setFill];
            [self.randomColorPrimary setStroke];
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
        int bin_size = floor(self.outDataLength/(self.numBars*2));
        CGRect barRect;
        CGFloat centerX = (rect.size.width/2.0);
        CGFloat centerY = (rect.size.height/2.0);
        CGFloat frameHeight = rect.size.height * self.barHeight;

        if(self.colorStyle == 0)
        {
            [self.secondaryColor setFill];
            [self.secondaryColor setStroke];
        }
        else if(self.colorStyle == 1)
        {
            [self.colorFlowSecondary setFill];
            [self.colorFlowSecondary setStroke];
        }
        else if(self.colorStyle == 2)
        {
            [self.prismFlowSecondary setFill];
            [self.prismFlowSecondary setStroke];
        }
        else if(self.colorStyle == 3)
        {
            [self.randomColorSecondary setFill];
            [self.randomColorSecondary setStroke];
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
                self.sum +=[[currentSpectrumData objectAtIndex:((i * bin_size) + j)] floatValue];
            }
            self.avg = self.sum/bin_size;
            self.bar_width = (rect.size.width/(self.numBars*2))*2.0;
            self.scaled_avg = (self.avg / self.mag ) * frameHeight * self.volume;

            if(self.scaled_avg != self.scaled_avg)
            {
                self.scaled_avg = frameHeight;
            }

            if(self.scaled_avg > frameHeight)
                self.scaled_avg = frameHeight;

            UIBezierPath * barPath;
            if(self.spectrumStyle == 0)
            {
                barRect = CGRectMake(i*self.bar_width,(frameHeight-self.scaled_avg) + ((1.0-self.barHeight) * rect.size.height),self.bar_width, self.scaled_avg);
                barPath = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:0];
            }
            else if(self.spectrumStyle == 1)
            {
                barRect = CGRectMake(i*self.bar_width,(frameHeight/2.0-self.scaled_avg/2.0) + ((1.0-self.barHeight) * (rect.size.height/2.0)),self.bar_width, self.scaled_avg);
                barPath = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:0];
            }
            else if(self.spectrumStyle == 2 || self.spectrumStyle == 3)
            {
                if(self.spectrumStyle == 2)
                {
                   barRect = CGRectMake((rect.size.height/2.0)-(self.bar_width),((rect.size.width/4.0) - (self.scaled_avg/4.0)),self.bar_width, self.scaled_avg/4.0);
                }
                else
                    barRect = CGRectMake((rect.size.height/2.0)-(self.bar_width),((rect.size.width/4.0) - (self.scaled_avg/4.0)),self.bar_width, self.scaled_avg/2.0);

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
    else if(self.type == 3.0)
    {
        UIColor * backgroundColor = [UIColor clearColor];
        UIColor * barBackgroundColor = [UIColor colorWithRed:1.f green:1.f blue:1.f alpha:0.2f];
        UIColor * barFillColor = [UIColor colorWithRed:0.98f green:0.36f blue:0.36f alpha:1.f];

        CGFloat columnMargin = 1.f;
        CGFloat columnWidth = 24.f;
        BOOL showsBlocks = YES;

        NSUInteger count = currentSpectrumData.count;
        CGFloat maxWidth = rect.size.width;
        CGFloat maxHeight = rect.size.height;
        
        CGFloat offset = columnMargin;
        CGFloat width = columnWidth;

        CGFloat screenScale = [[UIScreen mainScreen] scale];

        const CGFloat kDefaultMinDbLevel = -40.f;
        const CGFloat kDefaultMinDbFS = -110.f;
        const CGFloat kDBLogFactor = 4.0f;
                
        if (width <= 0.f)
        {
            if (count > 0)
            {
                width = (maxWidth - (count - 1) * offset) / count;
                width = floorf(width);
            }
        }
        
        CGFloat restSpace = maxWidth - (count * width + (count - 1) * offset);
        CGFloat x = restSpace/2.f;
        
        if (showsBlocks)
        {
            int blocksCount = maxHeight/width;
            
            if (blocksCount > 0)
            {
                CGFloat lineWidth = 1.f/screenScale;
                CGFloat y = rect.size.height + lineWidth;
                                
                UIBezierPath *clipBezierPath = [UIBezierPath bezierPath];

                for (int i = 0; i < blocksCount; i++)
                {
                    [clipBezierPath appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(0.f, y, maxWidth, width)]];
                    
                    y -= width + lineWidth;
                }
             
                [clipBezierPath closePath];
                [clipBezierPath addClip];
            }
        }
        
        UIBezierPath *barBackgroundPath = [UIBezierPath bezierPath];
        UIBezierPath *barFillPath = [UIBezierPath bezierPath];

        for (int i = 0; i < count; i++)
        {
            CGRect frame = CGRectMake(x, 0.f, width, maxHeight);
            
            [barBackgroundPath appendPath:[UIBezierPath bezierPathWithRect:frame]];

            CGFloat floatValue = [[currentSpectrumData objectAtIndex:i] floatValue];

            if (!isnan(floatValue))
            {

                //CGFloat scaled_avg = floatValue * (rect.size.height/1.5) * self.volume;
                CGFloat scaled_avg = floatValue * (maxHeight/1.5) * self.volume;
                //self.scaled_avg = (self.avg / self.mag ) * frameHeight * self.volume;

                if(scaled_avg > maxHeight)
                    scaled_avg = maxHeight;

                floatValue = scaled_avg;

                /*CGFloat height = 0.f;

                if (floatValue <= kDefaultMinDbLevel)
                {
                    height = 1.f/screenScale;
                }
                else if (floatValue >= 0)
                {
                    height = maxHeight - 1.f/screenScale;
                }
                else
                {
                    float normalizedValue = (kDefaultMinDbLevel - floatValue)/kDefaultMinDbLevel;
    //                normalizedValue = pow(normalizedValue, 1.0/kDBLogFactor);
                    height = floor(normalizedValue * maxHeight) + 0.5f;
                    
    //                NSLog(@"db: %8.4f, h: %8.4f", floatValue, normalizedValue);
                }*/
                
                frame.origin.y = maxHeight - floatValue;
                frame.size.height = floatValue;
                
                [barFillPath appendPath:[UIBezierPath bezierPathWithRect:frame]];
            }
            
            x += width + offset;
        }
        
        [barBackgroundColor setFill];
        [barBackgroundPath fill];
        
        [barFillColor setFill];
        [barFillPath fill];
    }
    else
    {
        //NSLog(@"[Prism]Not a valid type");
    }
}

/*- (void)adjustData
{
    self.max  = 0.0;
    CGPoint *points = self.points;
    for (int i = 0; i < 100; i++)
    {
        points[i].x = i;
        float y = self.outData[i+100];
        if( y > self.max)
            self.max = y;
        if(y > 1 )
            points[i].y = 1;
        else
            points[i].y = y;
    }
    points[0].y = points[100 - 1].y = 0.0f;
    NSLog(@"Max: %f", self.max);
    self.pointCount = 100;
}*/

- (void)redraw
{
    CGRect frame = [self.waveformLayer frame];
    CGPathRef path = [self createPathWithPoints:self.points
                                     pointCount:self.pointCount
                                         inRect:frame];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.waveformLayer.path = path;
    [CATransaction commit];

    CGPathRelease(path);
}

//------------------------------------------------------------------------------

- (CGPathRef)createPathWithPoints:(CGPoint *)points
                  pointCount:(UInt32)pointCount
                      inRect:(CGRect)rect
{
    CGMutablePathRef path = NULL;
    if (pointCount > 0)
    {
        path = CGPathCreateMutable();
        double xscale = (rect.size.width) / ((float)self.pointCount);
        double halfHeight = floor(rect.size.height / 2.0);
        int deviceOriginFlipped = -1;
        CGAffineTransform xf = CGAffineTransformIdentity;
        CGFloat translateY = 0.0f;

        translateY = halfHeight + rect.origin.y;
        
        xf = CGAffineTransformTranslate(xf, 0.0, translateY);
        double yScaleFactor = halfHeight;
        xf = CGAffineTransformScale(xf, xscale, deviceOriginFlipped * yScaleFactor);
        CGPathAddLines(path, &xf, self.points, self.pointCount);

        //xf = CGAffineTransformScale(xf, 1.0f, -1.0f);
        //CGPathAddLines(path, &xf, self.points, self.pointCount);
        
        CGPathCloseSubpath(path);
    }
    return path;
}

@end

@implementation AudioPlotWaveformLayer

- (id<CAAction>)actionForKey:(NSString *)event
{
    if ([event isEqualToString:@"path"])
    {
        if ([CATransaction disableActions])
        {
            return nil;
        }
        else
        {
            CABasicAnimation *animation = [CABasicAnimation animation];
            animation.timingFunction = [CATransaction animationTimingFunction];
            animation.duration = [CATransaction animationDuration];
            return animation;
        }
        return nil;
    }
    return [super actionForKey:event];
}

@end