#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@implementation NSBundle (VersionSpoof)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [NSBundle class];
        
        // 1. objectForInfoDictionaryKey: 후킹
        SEL origSel1 = @selector(objectForInfoDictionaryKey:);
        SEL swizSel1 = @selector(spoof_objectForInfoDictionaryKey:);
        Method origMethod1 = class_getInstanceMethod(cls, origSel1);
        Method swizMethod1 = class_getInstanceMethod(cls, swizSel1);
        if (origMethod1 && swizMethod1) {
            method_exchangeImplementations(origMethod1, swizMethod1);
        }
        
        // 2. infoDictionary 후킹
        SEL origSel2 = @selector(infoDictionary);
        SEL swizSel2 = @selector(spoof_infoDictionary);
        Method origMethod2 = class_getInstanceMethod(cls, origSel2);
        Method swizMethod2 = class_getInstanceMethod(cls, swizSel2);
        if (origMethod2 && swizMethod2) {
            method_exchangeImplementations(origMethod2, swizMethod2);
        }
    });
}

- (id)spoof_objectForInfoDictionaryKey:(NSString *)key {
    if (self == [NSBundle mainBundle] && [key isEqualToString:@"CFBundleShortVersionString"]) {
        return @"5.1.1";
    }
    return [self spoof_objectForInfoDictionaryKey:key];
}

- (NSDictionary *)spoof_infoDictionary {
    NSDictionary *dict = [self spoof_infoDictionary];
    if (self == [NSBundle mainBundle] && dict) {
        NSMutableDictionary *mutableDict = [dict mutableCopy];
        mutableDict[@"CFBundleShortVersionString"] = @"5.1.1";
        return [mutableDict copy];
    }
    return dict;
}

@end
