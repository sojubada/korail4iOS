#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <errno.h>
#import <string.h>

// ==========================================
// 1. fork() 및 getenv() 후킹 함수 정의
// ==========================================

static char *(*orig_getenv)(const char *name) = NULL;

// fork() 호출 시 일반 앱 샌드박스처럼 실패(-1) 및 EPERM 반환
static pid_t hooked_fork(void) {
    errno = EPERM;
    return -1;
}

// checkRuntime의 DYLD 환경변수 탐지 우회
static char *hooked_getenv(const char *name) {
    if (name && (strstr(name, "DYLD_") != NULL)) {
        return NULL;
    }
    return orig_getenv ? orig_getenv(name) : NULL;
}

// ==========================================
// 2. Mach-O 심볼 테이블 리바인딩 (fishhook 원리)
// ==========================================

static void rebind_symbols_for_image(const struct mach_header *header, intptr_t slide) {
    if (header->magic != MH_MAGIC_64) return;

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

    if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment) return;

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
                            uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
                            char *symbol_name = strtab + strtab_offset;

                            if (strcmp(symbol_name, "_fork") == 0) {
                                indirect_symbol_bindings[k] = (void *)hooked_fork;
                            } else if (strcmp(symbol_name, "_getenv") == 0) {
                                if (!orig_getenv) orig_getenv = (typeof(orig_getenv))indirect_symbol_bindings[k];
                                indirect_symbol_bindings[k] = (void *)hooked_getenv;
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
// 3. NSBundle 버전 패치 (5.1.1) 및 초기화
// ==========================================

@implementation NSBundle (VersionSpoof)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1) 로드되는 모든 바이너리/프레임워크(iScreenSAFER 포함)에 fork 및 getenv 후킹 등록
        _dyld_register_func_for_add_image(rebind_symbols_for_image);

        // 2) NSBundle 버전 스푸핑 (4.17.0 -> 5.1.1)
        Class cls = [NSBundle class];
        
        SEL origSel1 = @selector(objectForInfoDictionaryKey:);
        SEL swizSel1 = @selector(spoof_objectForInfoDictionaryKey:);
        method_exchangeImplementations(class_getInstanceMethod(cls, origSel1),
                                       class_getInstanceMethod(cls, swizSel1));
        
        SEL origSel2 = @selector(infoDictionary);
        SEL swizSel2 = @selector(spoof_infoDictionary);
        method_exchangeImplementations(class_getInstanceMethod(cls, origSel2),
                                       class_getInstanceMethod(cls, swizSel2));
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
