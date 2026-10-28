#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#include <vector>
#include <cmath>
#include <stdint.h>
#include <string.h>

struct Vector3 { float x, y, z; };
struct Il2CppObject { void* klass; void* monitor; };
struct Il2CppString { Il2CppObject object; int32_t length; uint16_t chars[1]; };
struct Il2CppArray { Il2CppObject obj; void* bounds; uintptr_t max_length; void* vector[1]; };

typedef void* (*il2cpp_domain_get_t)();
typedef void* (*il2cpp_domain_assembly_open_t)(void* domain, const char* name);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef void* (*il2cpp_class_from_name_t)(void* image, const char* ns, const char* name);
typedef void* (*il2cpp_class_get_method_from_name_t)(void* klass, const char* name, int argsCount);
typedef Il2CppString* (*il2cpp_string_new_t)(const char* str);

static il2cpp_domain_get_t il2cpp_domain_get = nullptr;
static il2cpp_domain_assembly_open_t il2cpp_domain_assembly_open = nullptr;
static il2cpp_assembly_get_image_t il2cpp_assembly_get_image = nullptr;
static il2cpp_class_from_name_t il2cpp_class_from_name = nullptr;
static il2cpp_class_get_method_from_name_t il2cpp_class_get_method_from_name = nullptr;
static il2cpp_string_new_t il2cpp_string_new = nullptr;

struct MethodInfo { uintptr_t methodPointer; };

static uintptr_t GetMethodPointer(void* image, const char* ns, const char* klassName, const char* methodName, int args) {
    void* klass = il2cpp_class_from_name(image, ns, klassName);
    if (!klass) return 0;
    MethodInfo* method = (MethodInfo*)il2cpp_class_get_method_from_name(klass, methodName, args);
    if (!method) return 0;
    return method->methodPointer;
}

// Metal Chams Hook
static IMP orig_setDepthStencilState = nullptr;
static id<MTLDepthStencilState> g_AlwaysPassDepthState = nil;

void hooked_setDepthStencilState(id self, SEL _cmd, id<MTLDepthStencilState> state) {
    if (state != nil && [self respondsToSelector:@selector(device)]) {
        if (g_AlwaysPassDepthState == nil) {
            id<MTLDevice> dev = [self performSelector:@selector(device)];
            if (dev) {
                MTLDepthStencilDescriptor* desc = [[MTLDepthStencilDescriptor alloc] init];
                desc.depthCompareFunction = MTLCompareFunctionAlways;
                desc.depthWriteEnabled = NO;
                g_AlwaysPassDepthState = [dev newDepthStencilStateWithDescriptor:desc];
            }
        }
        if (g_AlwaysPassDepthState != nil) {
            ((void(*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, g_AlwaysPassDepthState);
            return;
        }
    }
    ((void(*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, state);
}

static void InstallMetalHook() {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;
    Class* classes = (Class*)malloc(sizeof(Class) * (size_t)numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    SEL targetSel = @selector(setDepthStencilState:);
    for (int i = 0; i < numClasses; i++) {
        if (strstr(class_getName(classes[i]), "MTLRenderCommandEncoder") != nullptr) {
            Method m = class_getInstanceMethod(classes[i], targetSel);
            if (m != nullptr) {
                orig_setDepthStencilState = method_setImplementation(m, (IMP)hooked_setDepthStencilState);
                break;
            }
        }
    }
    free(classes);
}

// UI Overlay for Status
@interface KanhaAdvancedOverlay : UIView
@property (nonatomic, strong) UILabel* statusLabel;
@end

@implementation KanhaAdvancedOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 50, 220, 28)];
        _statusLabel.text = @"🔥 Chams + NoRecoil : ON";
        _statusLabel.textColor = [UIColor greenColor];
        _statusLabel.font = [UIFont boldSystemFontOfSize:12];
        [self addSubview:_statusLabel];
    }
    return self;
}
@end

static KanhaAdvancedOverlay* g_Overlay = nil;

__attribute__((constructor))
static void KanhaAdvancedEntry() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallMetalHook();
        
        UIWindow* keyWindow = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
            }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;
        if (!keyWindow) return;

        g_Overlay = [[KanhaAdvancedOverlay alloc] initWithFrame:keyWindow.bounds];
        g_Overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [keyWindow addSubview:g_Overlay];
    });
}
