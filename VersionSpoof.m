#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <errno.h>
#import <string.h>

// ==========================================
// 1. 원본 함수 포인터 및 후킹 함수 정의
// ==========================================

static void *real_fork_ptr = NULL;
static void *real_getenv_ptr = NULL;
static void *real_dlsym_ptr = NULL;

static pid_t hooked_fork(void) {
    errno = EPERM;
    return -1;
}

static char *hooked_getenv(const char *name) {
    if (name && (strstr(name, "DYLD_") != NULL || strstr(name, "Inject") != NULL)) {
        return NULL;
    }
    if (real_getenv_ptr) {
        return ((char *(*)(const char *))real_getenv_ptr)(name);
    }
    return NULL;
}

// 탐지기가 dlsym(RTLD_DEFAULT, "fork")로 우회 호출하는 경우까지 완벽 차단
static void *hooked_dlsym(void *handle, const char *symbol) {
    if (symbol) {
        if (strcmp(symbol, "fork") == 0 || strcmp(symbol, "_fork") == 0) {
            return (void *)hooked_fork;
        }
        if (strcmp(symbol, "getenv") == 0 || strcmp(symbol, "_getenv") == 0) {
            return (void *)hooked_getenv;
        }
    }
    if (real_dlsym_ptr) {
        return ((void *(*)(void *, const char *))real_dlsym_ptr)(handle, symbol);
    }
    return NULL;
}

// ==========================================
// 2. 안전한 메모리 포인터 덮어쓰기
// ==========================================

static void safe_write_pointer(void **target, void *replacement) {
    vm_address_t addr = (vm_address_t)target;
    vm_address_t page_start = trunc_page(addr);
    vm_size_t page_size = vm_page_size;

    // 1차: r--/rw- 페이지 권한 해제
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        // 2차: Copy-On-Write 요청
        kr = vm_protect(mach_task_self(), page_start, page_size, FALSE,
                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    }

    if (kr == KERN_SUCCESS) {
        *target = replacement;
        vm_protect(mach_task_self(), page_start, page_size, FALSE, VM_PROT_READ);
    }
}

// ==========================================
// 3. Chained Fixups 대응: GOT 포인터 직접 스캔 후킹
// ==========================================

static void scan_and_hook_image(const struct mach_header *header, intptr_t slide) {
    if (header->magic != MH_MAGIC_64) return;

    Dl_info info;
    if (dladdr(header, &info) == 0 || !info.dli_fname) return;

    // 우리 자신의 dylib는 제외하고, 앱 번들 내부(Korail 본체 및 iScreenSAFER 등 프레임워크)만 스캔
    if (strstr(info.dli_fname, "VersionSpoof") != NULL) return;
    if (strstr(info.dli_fname, ".app/") == NULL) return;

    struct mach_header_64 *header64 = (struct mach_header_64 *)header;
    struct load_command *cmd = (struct load_command *)((uintptr_t)header64 + sizeof(struct mach_header_64));

    for (uint32_t i = 0; i < header64->ncmds; i++) {
        if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)cmd;
            if (strcmp(seg->segname, "__DATA") == 0 ||
                strcmp(seg->segname, "__DATA_CONST") == 0 ||
                strcmp(seg->segname, "__AUTH") == 0 ||
                strcmp(seg->segname, "__AUTH_CONST") == 0) {

                struct section_64 *sec = (struct section_64 *)((uintptr_t)seg + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    // GOT 및 심볼 포인터가 위치하는 섹션만 안전하게 스캔
                    if (strstr(sec[j].sectname, "got") != NULL ||
                        strstr(sec[j].sectname, "symbol_ptr") != NULL ||
                        strstr(sec[j].sectname, "const") != NULL) {

                        void **pointers = (void **)((uintptr_t)slide + sec[j].addr);
                        size_t count = sec[j].size / sizeof(void *);

                        for (size_t k = 0; k < count; k++) {
                            void *ptr = pointers[k];
                            if (!ptr) continue;

                            if (real_fork_ptr && ptr == real_fork_ptr) {
                                safe_write_pointer(&pointers[k], (void *)hooked_fork);
                            } else if (real_getenv_ptr && ptr == real_getenv_ptr) {
                                safe_write_pointer(&pointers[k], (void *)hooked_getenv);
                            } else if (real_dlsym_ptr && ptr == real_dlsym_ptr) {
                                safe_write_pointer(&pointers[k], (void *)hooked_dlsym);
                            }
                        }
                    }
                }
            }
        }
        cmd = (struct load_command *)((uintptr_t)cmd + cmd->cmdsize);
    }
}

// ==========================================
// 4. Objective-C 메서드 후킹 (보조 방어)
// ==========================================

static BOOL return_false_imp(id self, SEL _cmd) {
    return NO;
}

static void hook_objc_methods(const struct mach_header *header, intptr_t slide) {
    SEL targets[] = {
        sel_registerName("isJailBroken"),
        sel_registerName("isSandboxIntegrityCompromised"),
        sel_registerName("checkRuntime"),
        sel_registerName("isJailBreakFilesExist"),
        sel_registerName("checkURLSchemes"),
        sel_registerName("checkRestrictedDirectoriesWritable"),
        sel_registerName("isSymbolicLink")
    };
    size_t targetCount = sizeof(targets) / sizeof(targets[0]);

    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;

    Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        const char *className = class_getName(classes[i]);
        if (strstr(className, "Jailbreak") != NULL || strstr(className, "iScreenSAFER") != NULL) {
            Class cls = classes[i];
            Class metaCls = object_getClass(cls);
            for (size_t t = 0; t < targetCount; t++) {
                Method m1 = class_getInstanceMethod(cls, targets[t]);
                if (m1) method_setImplementation(m1, (IMP)return_false_imp);
                Method m2 = class_getClassMethod(cls, targets[t]);
                if (m2) method_setImplementation(m2, (IMP)return_false_imp);
                Method m3 = class_getInstanceMethod(metaCls, targets[t]);
                if (m3) method_setImplementation(m3, (IMP)return_false_imp);
            }
        }
    }
    free(classes);
}

static void image_load_callback(const struct mach_header *header, intptr_t slide) {
    scan_and_hook_image(header, slide);
    hook_objc_methods(header, slide);
}

// ==========================================
// 5. 초기화 및 버전 패치 (5.1.1)
// ==========================================

@implementation NSBundle (VersionSpoof)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1) 실제 시스템 함수 주소 확보
        real_fork_ptr = dlsym(RTLD_DEFAULT, "fork");
        real_getenv_ptr = dlsym(RTLD_DEFAULT, "getenv");
        real_dlsym_ptr = dlsym(RTLD_DEFAULT, "dlsym");

        // 2) 버전 스푸핑 (5.1.1)
        Class cls = [NSBundle class];
        method_exchangeImplementations(class_getInstanceMethod(cls, @selector(objectForInfoDictionaryKey:)),
                                       class_getInstanceMethod(cls, @selector(spoof_objectForInfoDictionaryKey:)));
        method_exchangeImplementations(class_getInstanceMethod(cls, @selector(infoDictionary)),
                                       class_getInstanceMethod(cls, @selector(spoof_infoDictionary)));

        // 3) 모든 이미지 로드 콜백 등록 (Chained Fixups GOT 직접 스캔)
        _dyld_register_func_for_add_image(image_load_callback);
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
