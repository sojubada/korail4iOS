#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

// ==========================================
// 1. 숨길 파일 및 키워드 필터링
// ==========================================

static BOOL is_restricted_path(const char *path) {
    if (!path) return NO;
    const char *keywords[] = {
        "Cydia", "cydia", "saurik",
        "Sileo", "sileo", "coolstar",
        "Zebra", "zbra",
        "Substrate", "substrate", "Substitute", "substitute",
        "TweakInject", "libhooker", "ElleKit",
        "/jb/", "/var/jb", "/bin/bash", "/usr/sbin/sshd", "/etc/apt",
        "TrollStore", "Filza"
    };
    size_t count = sizeof(keywords) / sizeof(keywords[0]);
    for (size_t i = 0; i < count; i++) {
        if (strstr(path, keywords[i]) != NULL) {
            return YES;
        }
    }
    return NO;
}

// ==========================================
// 2. 원본 함수 포인터 및 후킹 함수 정의
// ==========================================

static void *real_fork_ptr = NULL;
static void *real_getenv_ptr = NULL;
static void *real_stat_ptr = NULL;
static void *real_lstat_ptr = NULL;
static void *real_access_ptr = NULL;
static void *real_fopen_ptr = NULL;

static pid_t hooked_fork(void) {
    errno = EPERM;
    return -1;
}

static char *hooked_getenv(const char *name) {
    if (name && (strstr(name, "DYLD_") != NULL || strstr(name, "Inject") != NULL)) {
        return NULL;
    }
    return real_getenv_ptr ? ((char *(*)(const char *))real_getenv_ptr)(name) : NULL;
}

static int hooked_stat(const char *path, struct stat *buf) {
    if (is_restricted_path(path)) {
        errno = ENOENT;
        return -1;
    }
    return real_stat_ptr ? ((int (*)(const char *, struct stat *))real_stat_ptr)(path, buf) : -1;
}

static int hooked_lstat(const char *path, struct stat *buf) {
    if (is_restricted_path(path)) {
        errno = ENOENT;
        return -1;
    }
    return real_lstat_ptr ? ((int (*)(const char *, struct stat *))real_lstat_ptr)(path, buf) : -1;
}

static int hooked_access(const char *path, int amode) {
    if (is_restricted_path(path)) {
        errno = ENOENT;
        return -1;
    }
    return real_access_ptr ? ((int (*)(const char *, int))real_access_ptr)(path, amode) : -1;
}

static FILE *hooked_fopen(const char *path, const char *mode) {
    if (is_restricted_path(path)) {
        errno = ENOENT;
        return NULL;
    }
    return real_fopen_ptr ? ((FILE *(*)(const char *, const char *))real_fopen_ptr)(path, mode) : NULL;
}

// ==========================================
// 3. 안전한 메모리 쓰기 및 GOT 스캔
// ==========================================

static void safe_write_pointer(void **target, void *replacement) {
    vm_address_t addr = (vm_address_t)target;
    vm_address_t page_start = trunc_page(addr);
    vm_size_t page_size = vm_page_size;

    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        kr = vm_protect(mach_task_self(), page_start, page_size, FALSE,
                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    }
    if (kr == KERN_SUCCESS) {
        *target = replacement;
        vm_protect(mach_task_self(), page_start, page_size, FALSE, VM_PROT_READ);
    }
}

static void scan_and_hook_image(const struct mach_header *header, intptr_t slide) {
    if (header->magic != MH_MAGIC_64) return;

    Dl_info info;
    if (dladdr(header, &info) == 0 || !info.dli_fname) return;
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
                    if (strstr(sec[j].sectname, "got") != NULL ||
                        strstr(sec[j].sectname, "symbol_ptr") != NULL ||
                        strstr(sec[j].sectname, "const") != NULL) {

                        void **pointers = (void **)((uintptr_t)slide + sec[j].addr);
                        size_t count = sec[j].size / sizeof(void *);

                        for (size_t k = 0; k < count; k++) {
                            void *ptr = pointers[k];
                            if (!ptr) continue;

                            if (real_fork_ptr && ptr == real_fork_ptr) safe_write_pointer(&pointers[k], (void *)hooked_fork);
                            else if (real_getenv_ptr && ptr == real_getenv_ptr) safe_write_pointer(&pointers[k], (void *)hooked_getenv);
                            else if (real_stat_ptr && ptr == real_stat_ptr) safe_write_pointer(&pointers[k], (void *)hooked_stat);
                            else if (real_lstat_ptr && ptr == real_lstat_ptr) safe_write_pointer(&pointers[k], (void *)hooked_lstat);
                            else if (real_access_ptr && ptr == real_access_ptr) safe_write_pointer(&pointers[k], (void *)hooked_access);
                            else if (real_fopen_ptr && ptr == real_fopen_ptr) safe_write_pointer(&pointers[k], (void *)hooked_fopen);
                        }
                    }
                }
            }
        }
        cmd = (struct load_command *)((uintptr_t)cmd + cmd->cmdsize);
    }
}

// ==========================================
// 4. NSFileManager 및 NSBundle 후킹
// ==========================================

@implementation NSFileManager (HideJailbreakFiles)

- (BOOL)spoof_fileExistsAtPath:(NSString *)path {
    if (path && is_restricted_path([path UTF8String])) {
        return NO;
    }
    return [self spoof_fileExistsAtPath:path];
}

- (BOOL)spoof_fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (path && is_restricted_path([path UTF8String])) {
        return NO;
    }
    return [self spoof_fileExistsAtPath:path isDirectory:isDirectory];
}

@end

@implementation NSBundle (VersionSpoof)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        real_fork_ptr = dlsym(RTLD_DEFAULT, "fork");
        real_getenv_ptr = dlsym(RTLD_DEFAULT, "getenv");
        real_stat_ptr = dlsym(RTLD_DEFAULT, "stat");
        real_lstat_ptr = dlsym(RTLD_DEFAULT, "lstat");
        real_access_ptr = dlsym(RTLD_DEFAULT, "access");
        real_fopen_ptr = dlsym(RTLD_DEFAULT, "fopen");

        // 1) 버전 패치 (5.1.1)
        Class bundleCls = [NSBundle class];
        method_exchangeImplementations(class_getInstanceMethod(bundleCls, @selector(objectForInfoDictionaryKey:)),
                                       class_getInstanceMethod(bundleCls, @selector(spoof_objectForInfoDictionaryKey:)));
        method_exchangeImplementations(class_getInstanceMethod(bundleCls, @selector(infoDictionary)),
                                       class_getInstanceMethod(bundleCls, @selector(spoof_infoDictionary)));

        // 2) NSFileManager 경로 숨김 (saurik.Cydia.plist, coolstar.SileoStore.plist 등 차단)
        Class fmCls = [NSFileManager class];
        method_exchangeImplementations(class_getInstanceMethod(fmCls, @selector(fileExistsAtPath:)),
                                       class_getInstanceMethod(fmCls, @selector(spoof_fileExistsAtPath:)));
        method_exchangeImplementations(class_getInstanceMethod(fmCls, @selector(fileExistsAtPath:isDirectory:)),
                                       class_getInstanceMethod(fmCls, @selector(spoof_fileExistsAtPath:isDirectory:)));

        // 3) C 레벨 파일/프로세스 함수 후킹 등록
        _dyld_register_func_for_add_image(scan_and_hook_image);
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
