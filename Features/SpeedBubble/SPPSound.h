// Am canh bao qua toc do (Cai dat > Bong bong toc do > Canh bao qua toc do > Am thanh): am bao tu tong hop + giong noi.
// Dung chung: SpringBoard (SPPWarn.mm phat khi vuot) va trang Cai dat (Prefs/SPPSoundPrefs.m: cham 1 muc de nghe thu),
// nen nghe thu dung nhu tren xe. Ban duyet: tools/preview/index.html#bubble (TONES / VOICES / playSnd).
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
// Cau giong noi so i (0..SB_VOICE_COUNT-1) theo ngon ngu OmniCar (OMCTr), con "{L}" cho gioi han
NSString *SPPVoiceTemplate(NSInteger i);
BOOL SPPVoiceIsFun(NSInteger i);                     // nhom "Vui ve" (con lai "Nghiem tuc")
// Cau se noi: voice = chi so hoac SB_VOICE_CUSTOM (custom rong -> cau 0); limit = so tren bien (theo don vi dang hien), <= 0 = bo so
NSString *SPPVoiceLine(NSInteger voice, NSString *custom, int limit);
void SPPPlayTone(NSInteger tone);                    // 0..SB_TONE_COUNT-1: Bip, Bip doi, Bip gap, Chuong, Ping, Radar
void SPPSpeak(NSString *text);                       // doc bang giong cua ngon ngu OmniCar, cat cau dang doc
#ifdef __cplusplus
}
#endif
