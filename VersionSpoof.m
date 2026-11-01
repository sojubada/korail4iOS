#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <errno.h>
#import <string.h>

// ==========================================
// 1. C 함수 후킹 (fork / getenv) 및 안전한 메모리 쓰기
// ==========================================

static pid_t hooked_fork(void) {
    errno = EPERM;
    return -1;
}

static char *hooked_getenv(const char *name) {
    if (name && (strstr(name, "DYLD_") != NULL)) {
        return NULL;
    }
    static char *(*real_getenv)(const char *) = NULL;
    if (!real_getenv) {
        real_getenv = (char *(*)(const char *))dlsym(RTLD_NEXT, "getenv");
    }
    return real_getenv ? real_getenv(name) : NULL;
}

// PRT/MAX가 r--/rw- 인 __DATA_CONST 영역을 안전하게 수정
static void safe_write_pointer(void **target, void *replacement) {
    vm_address_t addr = (vm_address_t)target;
    vm_address_t page_start = trunc_page(addr);
    vm_size_t page_size = vm_page_size;

    // 1차 시도: MAX 권한(rw-)에 맞춰 VM_PROT_COPY 없이 요청
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_size, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        // 2차 시도: 공유 페이지일 경우 VM_PROT_COPY 포함 요청
        kr = vm_protect(mach_task_self(), page_start, page_size, FALSE,
                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    }

    if (kr == KERN_SUCCESS) {
        *target = replacement;
        // 수정 후 다시 읽기 전용(r--)으로 복원
        vm_protect(mach_task_self(), page_start, page_size, FALSE, VM_PROT_READ);
    }
}

// ==========================================
// 2. iScreenSAFER 전용 심볼 리바인딩
// ==========================================

static void rebind_symbols_for_image(const struct mach_header *header, intptr_t slide) {
    if (header->magic != MH_MAGIC_64) return;

    Dl_info info;
    if (dladdr(header, &info) == 0 || !info.dli_fname) return;

    // Korail 메인 바이너리 등 불필요한 이미지는 건너뛰고 iScreenSAFER만 정밀 타겟팅
    if (strstr(info.dli_fname, "iScreenSAFER") == NULL) {
        return;
    }

    struct mach_header_64 *header64 = (struct mach_header_64 *)header;
    struct load_command *cmd = (struct load_command *)((uintptr_t)header64 + sizeof(struct mach_header_64));

    struct symtab_command *symtab_cmd = NULL;
    struct dysymtab_command *dysymtab_cmd = NULL;
    struct segment_command_64 *linkedit_segment = NULL;

    for (uint32_t i = 0; i < header64->ncmds; i++) {
        if (cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cmd;
        } else if (cmd->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command *)cmd;
        } else if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)cmd;
            if (strcmp(seg->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = seg;
            }
        }
        cmd = (struct load_command *)((uintptr_t)cmd + cmd->cmdsize);
    }

    if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment || dysymtab_cmd->nindirectsyms == 0) return;

    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    struct nlist_64 *symtab = (struct nlist_64 *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

    cmd = (struct load_command *)((uintptr_t)header64 + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < header64->ncmds; i++) {
        if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)cmd;
            if (strcmp(seg->segname, SEG_DATA) == 0 || strcmp(seg->segname, "__DATA_CONST") == 0) {
                struct section_64 *sec = (struct section_64 *)((uintptr_t)seg + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    uint8_t type = sec[j].flags & SECTION_TYPE;
                    if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
                        uint32_t *indirect_symbol_indices = indirect_symtab + sec[j].reserved1;
                        void **indirect_symbol_bindings = (void **)((uintptr_t)slide + sec[j].addr);
                        size_t count = sec[j].size / sizeof(void *);

                        for (size_t k = 0; k < count; k++) {
                            uint32_t symtab_index = indirect_symbol_indices[k];
                            if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
                                symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
                                continue;
                            }
                            if (symtab_index >= symtab_cmd->nsyms) continue;

                            uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
                            if (strtab_offset >= symtab_cmd->strsize) continue;

                            char *symbol_name = strtab + strtab_offset;

                            if (strcmp(symbol_name, "_fork") == 0) {
                                safe_write_pointer(&indirect_symbol_bindings[k], (void *)hooked_fork);
                            } else if (strcmp(symbol_name, "_getenv") == 0) {
                                safe_write_pointer(&indirect_symbol_bindings[k], (void *)hooked_getenv);
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
// 3. Objective-C 탐지 메서드 직접 무력화 (return NO)
// ==========================================

static BOOL return_false_imp(id self, SEL _cmd) {
    return NO;
}

static void hook_objc_Methods_if_present(void) {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;

    Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

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

    for (int i = 0; i < numClasses; i++) {
        const char *className = class_getName(classes[i]);
        // Swift 네임스페이스가 붙은 경우(예: iScreenSAFER.JailbreakSimulatorChecker)까지 모두 포함하여 검색
        if (strstr(className, "JailbreakSimulatorChecker") != NULL ||
            strstr(className, "iScreenSAFER") != NULL) {
            Class cls = classes[i];
            Class metaCls = object_getClass(cls);

            for (size_t t = 0; t < targetCount; t++) {
                Method instM = class_getInstanceMethod(cls, targets[t]);
                if (instM) method_setImplementation(instM, (IMP)return_false_imp);

                Method clsM = class_getClassMethod(cls, targets[t]);
                if (clsM) method_setImplementation(clsM, (IMP)return_false_imp);
                
                Method metaM = class_getInstanceMethod(metaCls, targets[t]);
                if (metaM) method_setImplementation(metaM, (IMP)return_false_imp);
            }
        }
    }
    free(classes);
}

// ==========================================
// 4. NSBundle 버전 패치 (5.1.1) 및 초기화
// ==========================================

@implementation NSBundle (VersionSpoof)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1) 버전 스푸핑 (5.1.1)
        Class cls = [NSBundle class];
        method_exchangeImplementations(class_getInstanceMethod(cls, @selector(objectForInfoDictionaryKey:)),
                                       class_getInstanceMethod(cls, @selector(spoof_objectForInfoDictionaryKey:)));
        method_exchangeImplementations(class_getInstanceMethod(cls, @selector(infoDictionary)),
                                       class_getInstanceMethod(cls, @selector(spoof_infoDictionary)));

        // 2) Objective-C/Swift(@objc) 탐지 메서드 무력화
        hook_objc_Methods_if_present();

        // 3) iScreenSAFER 프레임워크 전용 C 심볼(fork, getenv) 후킹
        _dyld_register_func_for_add_image(rebind_symbols_for_image);
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
