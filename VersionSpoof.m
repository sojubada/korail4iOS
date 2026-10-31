#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define TARGET_VERSION @"5.1.1"
#define TARGET_BUILD   @"5.1"   // 필요시 최신 빌드 번호로 수정
#define OLD_VERSION    @"4.17.0"

@implementation NSBundle (VersionSpoofExtended)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. NSBundle 메서드 후킹
        Class bundleCls = [NSBundle class];
        
        method_exchangeImplementations(
            class_getInstanceMethod(bundleCls, @selector(objectForInfoDictionaryKey:)),
            class_getInstanceMethod(bundleCls, @selector(spoof_objectForInfoDictionaryKey:))
        );
        method_exchangeImplementations(
            class_getInstanceMethod(bundleCls, @selector(infoDictionary)),
            class_getInstanceMethod(bundleCls, @selector(spoof_infoDictionary))
        );
        method_exchangeImplementations(
            class_getInstanceMethod(bundleCls, @selector(localizedInfoDictionary)),
            class_getInstanceMethod(bundleCls, @selector(spoof_localizedInfoDictionary))
        );

        // 2. NSMutableURLRequest 네트워크 헤더 후킹 (User-Agent 등 버전 노출 차단)
        Class reqCls = [NSMutableURLRequest class];
        method_exchangeImplementations(
            class_getInstanceMethod(reqCls, @selector(setValue:forHTTPHeaderField:)),
            class_getInstanceMethod(reqCls, @selector(spoof_setValue:forHTTPHeaderField:))
        );
    });
}

- (id)spoof_objectForInfoDictionaryKey:(NSString *)key {
    if (self == [NSBundle mainBundle]) {
        if ([key isEqualToString:@"CFBundleShortVersionString"]) {
            return TARGET_VERSION;
        }
        if ([key isEqualToString:@"CFBundleVersion"]) {
            return TARGET_BUILD;
        }
    }
    return [self spoof_objectForInfoDictionaryKey:key];
}

- (NSDictionary *)spoof_infoDictionary {
    NSDictionary *dict = [self spoof_infoDictionary];
    if (self == [NSBundle mainBundle] && dict) {
        NSMutableDictionary *mutableDict = [dict mutableCopy];
        mutableDict[@"CFBundleShortVersionString"] = TARGET_VERSION;
        mutableDict[@"CFBundleVersion"] = TARGET_BUILD;
        return [mutableDict copy];
    }
    return dict;
}

- (NSDictionary *)spoof_localizedInfoDictionary {
    NSDictionary *dict = [self spoof_localizedInfoDictionary];
    if (self == [NSBundle mainBundle] && dict) {
        NSMutableDictionary *mutableDict = [dict mutableCopy];
        mutableDict[@"CFBundleShortVersionString"] = TARGET_VERSION;
        mutableDict[@"CFBundleVersion"] = TARGET_BUILD;
        return [mutableDict copy];
    }
    return dict;
}

@end

@implementation NSMutableURLRequest (HeaderSpoof)

- (void)spoof_setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (value && [value containsString:OLD_VERSION]) {
        value = [value stringByReplacingOccurrencesOfString:OLD_VERSION withString:TARGET_VERSION];
    }
    [self spoof_setValue:value forHTTPHeaderField:field];
}

@end
