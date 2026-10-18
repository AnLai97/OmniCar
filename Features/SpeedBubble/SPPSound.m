// Am canh bao: xem SPPSound.h. Am bao tong hop giong het playSnd() trong tools/preview/index.html#bubble (tan so, dang song,
// bao am: len trong 12 ms roi tat dan theo ham mu), ghi thanh WAV trong thu muc tam roi phat bang am he thong (cung duong
// voi tieng bip cu: theo am luong chuong / cong tac im lang). Giong noi: AVSpeechSynthesizer.
#import "SPPSound.h"
#import "SpeedBubble.h"
#import "OmniCar.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define SPP_TONE_RATE 22050

NSString *SPPVoiceTemplate(NSInteger i)
{
    switch (i) {
    case 1: return OMCTr(@"Quá tốc độ, giới hạn {L}", @"Too fast, the limit is {L}");
    case 2: return OMCTr(@"Vui lòng giảm tốc độ", @"Please slow down");
    case 3: return OMCTr(@"Ê, xe chứ có phải máy bay đâu!", @"Hey, this is a car, not a plane!");
    case 4: return OMCTr(@"Bình tĩnh, đường còn dài mà ví thì còn mỏng", @"Easy now, the road is long and the wallet is thin");
    case 5: return OMCTr(@"Camera phạt nguội đang mỉm cười với bạn đó", @"The speed camera is smiling at you");
    case 6: return OMCTr(@"Chạy gì mà vội, cơm nhà vẫn còn nóng mà", @"What's the rush? Dinner at home is still hot");
    case 7: return OMCTr(@"Nhẹ chân ga thôi, chạy nhanh không làm bạn đẹp trai hơn đâu", @"Easy on the gas, speeding won't make you any better looking");
    default: return OMCTr(@"Bạn đang vượt quá giới hạn tốc độ", @"You are over the speed limit");
    }
}

BOOL SPPVoiceIsFun(NSInteger i) { return i >= 3 && i < SB_VOICE_COUNT; }

NSString *SPPVoiceLine(NSInteger voice, NSString *custom, int limit)
{
    NSString *t = voice == SB_VOICE_CUSTOM ? [custom stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    if (!t.length) t = SPPVoiceTemplate(voice == SB_VOICE_CUSTOM ? 0 : voice);
    t = [t stringByReplacingOccurrencesOfString:@"{L}" withString:limit > 0 ? [NSString stringWithFormat:@"%d", limit] : @""];
    return [t stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ,"]];
}

// 1 not: tan so, bat dau / do dai (giay), dang song (0 vuong, 1 sin, 2 tam giac), am luong (nhu WebAudio)
typedef struct { double f, at, d; int wave; double vol; } SPPNote;

static NSData *SPPToneWav(NSInteger tone)
{
    SPPNote n[4]; int count = 0;
    switch (tone) {
    case 1: n[0] = (SPPNote){1320, 0, .12, 0, .06}; n[1] = (SPPNote){1320, .18, .12, 0, .06}; count = 2; break;
    case 2: for (int i = 0; i < 3; i++) n[i] = (SPPNote){1500, .13 * i, .09, 0, .06}; count = 3; break;
    case 3: n[0] = (SPPNote){988, 0, .7, 1, .3}; n[1] = (SPPNote){784, .28, .9, 1, .3}; count = 2; break;
    case 4: n[0] = (SPPNote){1760, 0, .9, 1, .28}; count = 1; break;
    case 5: for (int i = 0; i < 4; i++) n[i] = (SPPNote){900 + i * 220, .2 * i, .1, 2, .2}; count = 4; break;
    default: n[0] = (SPPNote){1320, 0, .16, 0, .06}; count = 1; break;
    }
    double len = 0;
    for (int i = 0; i < count; i++) len = MAX(len, n[i].at + n[i].d + .05);
    NSUInteger frames = (NSUInteger)ceil(len * SPP_TONE_RATE);
    double *buf = calloc(frames, sizeof(double)), peak = 0;
    for (int k = 0; k < count; k++) {
        SPPNote x = n[k];
        double a = x.at + .012, b = x.at + x.d;
        for (NSUInteger s = (NSUInteger)(x.at * SPP_TONE_RATE); s < frames; s++) {
            double t = (double)s / SPP_TONE_RATE;
            if (t > b + .05) break;
            double env = t < a ? x.vol * (t - x.at) / .012 : t < b ? x.vol * pow(.0008 / x.vol, (t - a) / (b - a)) : .0008;
            double ph = 2 * M_PI * x.f * (t - x.at), w = sin(ph);
            if (x.wave == 0) w = w >= 0 ? 1 : -1;
            else if (x.wave == 2) w = 2 / M_PI * asin(w);
            buf[s] += env * w;
        }
    }
    for (NSUInteger s = 0; s < frames; s++) peak = MAX(peak, fabs(buf[s]));
    double gain = peak > 0 ? 0.8 / peak : 0;   // moi am cung do lon (trinh duyet: bip vuong nho hon chuong)
    NSMutableData *d = [NSMutableData dataWithLength:44 + frames * 2];
    uint8_t *p = d.mutableBytes;
    uint32_t dataLen = (uint32_t)(frames * 2), riff = 36 + dataLen, rate = SPP_TONE_RATE, byteRate = SPP_TONE_RATE * 2, fmtLen = 16;
    uint16_t pcm = 1, ch = 1, align = 2, bits = 16;
    memcpy(p, "RIFF", 4); memcpy(p + 4, &riff, 4); memcpy(p + 8, "WAVEfmt ", 8); memcpy(p + 16, &fmtLen, 4);
    memcpy(p + 20, &pcm, 2); memcpy(p + 22, &ch, 2); memcpy(p + 24, &rate, 4); memcpy(p + 28, &byteRate, 4);
    memcpy(p + 32, &align, 2); memcpy(p + 34, &bits, 2); memcpy(p + 36, "data", 4); memcpy(p + 40, &dataLen, 4);
    int16_t *pcmOut = (int16_t *)(p + 44);
    for (NSUInteger s = 0; s < frames; s++) pcmOut[s] = (int16_t)lround(MAX(-1, MIN(1, buf[s] * gain)) * 32767);
    free(buf);
    return d;
}

#ifdef SPP_SOUND_PREFS   // bundle Cai dat: khong co Core
#define SPPSoundLog(fmt, ...) NSLog(@"OmniCar SpeedBubble: " fmt, ##__VA_ARGS__)
#else
#define SPPSoundLog(fmt, ...) OMCLogWrite(@"SpeedBubble", [NSString stringWithFormat:@fmt, ##__VA_ARGS__])
#endif

// Phien am thanh: truoc day am bao phat bang am he thong (AudioServicesPlaySystemSound: theo cong tac im lang, ra loa
// iPhone) va giong noi bang phien rieng cua AVSpeechSynthesizer (trong SpringBoard phien do khong len tieng - log 18/10
// 10:26: "canh bao: noi ..." ma xe im). Lam nhu am man khoi dong (StartupScreen.x, da nghe duoc tren xe): phien chung
// cua process, Playback (khong theo cong tac im lang) + mix (nhac / dan duong tren xe khong bi ngat) + duck (nho nhac
// de nghe ro), bat khi phat, tat khi xong (NotifyOthersOnDeactivation: nhac to lai). Trang Cai dat (nghe thu) di cung duong.
static NSString *gSavedCategory;
static AVAudioSessionCategoryOptions gSavedOptions;
static int gPlaying;   // so viec dang phat (am bao / giong noi)

static void SPPAudioBegin(void)
{
    AVAudioSession *s = [AVAudioSession sharedInstance];
    if (gPlaying++ == 0 && !gSavedCategory) { gSavedCategory = s.category; gSavedOptions = s.categoryOptions; }
    NSError *e = nil;
    if (![s setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers error:&e])
        SPPSoundLog("am thanh: khong dat duoc phien Playback: %@", e);
    e = nil;
    if (![s setActive:YES error:&e]) SPPSoundLog("am thanh: khong bat duoc phien: %@", e);
    else SPPSoundLog("am thanh: phien bat, ra %@", s.currentRoute.outputs.firstObject.portType ?: @"?");
}

static void SPPAudioEnd(void)
{
    if (gPlaying <= 0 || --gPlaying > 0) return;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    if (gSavedCategory) [s setCategory:gSavedCategory withOptions:gSavedOptions error:nil];
    gSavedCategory = nil;
}

// Nhan "phat xong" cua AVAudioPlayer / AVSpeechSynthesizer -> tat phien
@interface SPPSoundDelegate : NSObject <AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate>
@end
@implementation SPPSoundDelegate
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag { SPPAudioEnd(); }
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error { SPPSoundLog("am thanh: loi giai ma %@", error); SPPAudioEnd(); }
- (void)speechSynthesizer:(AVSpeechSynthesizer *)s didFinishSpeechUtterance:(AVSpeechUtterance *)u { SPPAudioEnd(); }
- (void)speechSynthesizer:(AVSpeechSynthesizer *)s didCancelSpeechUtterance:(AVSpeechUtterance *)u { SPPAudioEnd(); }
@end

static SPPSoundDelegate *SPPDelegate(void)
{
    static SPPSoundDelegate *d;
    if (!d) d = [SPPSoundDelegate new];
    return d;
}

void SPPPlayTone(NSInteger tone)
{
    static AVAudioPlayer *player;
    static NSData *wavs[SB_TONE_COUNT];
    if (tone < 0 || tone >= SB_TONE_COUNT) tone = 0;
    if (!wavs[tone]) wavs[tone] = SPPToneWav(tone);
    if (player) { [player stop]; player = nil; }
    SPPAudioBegin();
    NSError *e = nil;
    player = [[AVAudioPlayer alloc] initWithData:wavs[tone] fileTypeHint:AVFileTypeWAVE error:&e];
    if (!player) {   // khong mo duoc: phat bang am he thong nhu cu (co the im tren xe)
        SPPSoundLog("am thanh: khong mo duoc am bao %ld: %@ -> am he thong", (long)tone, e);
        SPPAudioEnd();
        static SystemSoundID ids[SB_TONE_COUNT];
        if (!ids[tone]) {
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"omc-speedbubble-tone-%ld.wav", (long)tone]];
            SystemSoundID sid = 0;
            if ([wavs[tone] writeToFile:path atomically:YES] && AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:path], &sid) == noErr) ids[tone] = sid;
        }
        if (ids[tone]) AudioServicesPlaySystemSound(ids[tone]);
        return;
    }
    player.delegate = SPPDelegate();
    player.volume = 1;
    if (![player play]) { SPPSoundLog("am thanh: khong phat duoc am bao %ld", (long)tone); SPPAudioEnd(); }
}

// Ma giong theo ngon ngu OmniCar (AVSpeechSynthesisVoice can vung)
static NSString *SPPSpeechLanguage(void)
{
    NSDictionary *m = @{@"vi": @"vi-VN", @"en": @"en-US", @"es": @"es-ES", @"pt-BR": @"pt-BR", @"de": @"de-DE", @"fr": @"fr-FR",
        @"it": @"it-IT", @"ru": @"ru-RU", @"zh-Hans": @"zh-CN", @"ja": @"ja-JP", @"ko": @"ko-KR", @"ar": @"ar-SA", @"th": @"th-TH", @"id": @"id-ID"};
    return m[OMCCurrentLanguage()] ?: @"en-US";
}

void SPPSpeak(NSString *text)
{
    static AVSpeechSynthesizer *synth;
    if (!text.length) return;
    if (!synth) {
        synth = [AVSpeechSynthesizer new];
        synth.usesApplicationAudioSession = YES;   // dung phien cua process (SPPAudioBegin): phien rieng trong SpringBoard khong len tieng
        synth.delegate = SPPDelegate();
    }
    if (synth.speaking) [synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];   // didCancel -> SPPAudioEnd cua cau cu
    SPPAudioBegin();
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:SPPSpeechLanguage()];
    if (!voice) SPPSoundLog("am thanh: khong co giong %@, dung giong mac dinh", SPPSpeechLanguage());
    u.voice = voice;
    u.volume = 1;
    [synth speakUtterance:u];
}
