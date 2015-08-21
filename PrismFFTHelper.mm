#import <Accelerate/Accelerate.h>
#import "PrismFFTHelper.h"

static const UInt32 PrismFFTHelperInputBufferSize  = 2048;
static const UInt32 PrismFFTHelperMaxBlocksBeforeSkipping = 4;

@interface PrismFFTHelper ()
{
    float  * _window;
    float * _inReal;
    UInt32 _numberOfSamples;
    COMPLEX_SPLIT _split;
    FFTSetup _fftSetup;
}

@property (nonatomic, strong) NSOperationQueue * operationQueue;

@end

@implementation PrismFFTHelper

- (id)init
{
    if( self = [self initWithNumberOfSamples:PrismFFTHelperInputBufferSize])
    {

    }

    return self;
}

- (instancetype)initWithNumberOfSamples:(UInt32)numberOfSamples
{
    if( self = [super init])
    {
        _numberOfSamples = numberOfSamples;

        UInt32 nOver2 = _numberOfSamples/2;
        vDSP_Length log2n = log2f(_numberOfSamples);
        _fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
        _inReal = (float*)malloc(_numberOfSamples * sizeof(float));
        _window = (float*)malloc(_numberOfSamples * sizeof(float));
        _split.realp = (float*)malloc(nOver2 * sizeof(float));
        _split.imagp = (float*)malloc(nOver2 * sizeof(float));
        vDSP_hann_window(_window, _numberOfSamples, vDSP_HANN_DENORM);

        _operationQueue = [NSOperationQueue new];
        _operationQueue.maxConcurrentOperationCount = 1;
    }

    return self;
}

- (void) dealloc
{
    [self.operationQueue cancelAllOperations];

    vDSP_destroy_fftsetup(_fftSetup);
    free(_inReal);
    free(_window);
    free(_split.realp);
    free(_split.imagp);
}

-(void)performComputation:(AudioBufferList *)bufferListInOut numberFrames:(CMItemCount)numberFrames isNonInterleaved:(BOOL)isNonInterleaved completionHandler:(PrismFFTHelperCompletionBlock)completion
{
    if(!completion)
    {
        return;
    }

    if(self.operationQueue.operationCount > 1)
    {
        [self.operationQueue cancelAllOperations];
    }

    [self.operationQueue addOperationWithBlock:^
    {
        float leftVol = 0.0;
        float rightVol = 0.0;

        for (UInt32 i = 0; i < bufferListInOut->mNumberBuffers; i++)
        {
            AudioBuffer *pBuffer = &bufferListInOut->mBuffers[i];
            UInt32 cSamples = numberFrames * (isNonInterleaved ? 1 : pBuffer->mNumberChannels);
            
            float *pData = (float *)pBuffer->mData;
            
            float rms = 0.0f;
            for (UInt32 j = 0; j < cSamples; j++)
            {
                rms += pData[j] * pData[j];
            }
            if (cSamples > 0)
            {
                rms = sqrtf(rms / cSamples);
            }
            
            if (0 == i)
            {
                leftVol = rms;
            }
            if (1 == i || (0 == i && 1 == bufferListInOut->mNumberBuffers))
            {
                rightVol = rms;
            }
        }

        AudioBuffer * firstBuffer = &bufferListInOut->mBuffers[1];
        float * bufferData = (float*)firstBuffer->mData;
        vDSP_vmul(bufferData, 1 , _window, 1, _inReal, 1, _numberOfSamples);
        vDSP_ctoz((COMPLEX*)_inReal, 2, &_split, 1, _numberOfSamples/2);
        vDSP_Length log2n = log2f((float)_numberOfSamples);
        vDSP_fft_zrip(_fftSetup, &_split, 1, log2n, FFT_FORWARD);
        _split.imagp[0] = 0.0;

        NSMutableArray * outData = [NSMutableArray new];
        [outData addObject:[NSNumber numberWithFloat:0]];

        for(UInt32 i=1; i < _numberOfSamples/2; i++)
        {
            float power = sqrtf(_split.realp[i] * _split.realp[i] + _split.imagp[i] * _split.imagp[i]);     
            [outData addObject:[NSNumber numberWithFloat:power]];
        }

        completion(outData, (leftVol+rightVol)/2.0, _numberOfSamples/2);
    }];
}

@end