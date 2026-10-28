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

// Global Hile Durumu
static bool g_ModieActive = true;

// Metal Chams Hook
static IMP orig_setDepthStencilState = nullptr;
static id<MTLDepthStencilState> g_AlwaysPassDepthState = nil;

void hooked_setDepthStencilState(id self, SEL _cmd, id<MTLDepthStencilState> state) {
    if (g_ModieActive && state != nil && [self respondsToSelector:@selector(device)]) {
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

// ============================================================================
// %100 DOKUNMA GEÇİRGEN TEK TUŞ GÖRÜNÜMÜ
// ============================================================================

@interface ModieAbsolutePassView : UIView
@property (nonatomic, strong) UIButton* toggleButton;
@end

@implementation ModieAbsolutePassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _toggleButton.frame = CGRectMake(25, 55, 110, 36);
        _toggleButton.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.85];
        _toggleButton.layer.cornerRadius = 8.0;
        _toggleButton.layer.borderWidth = 1.5;
        _toggleButton.layer.borderColor = [UIColor systemGreenColor].CGColor;
        [_toggleButton setTitle:@"MODIE: ON" forState:UIControlStateNormal];
        [_toggleButton setTitleColor:[UIColor systemGreenColor] forState:UIControlStateNormal];
        _toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [_toggleButton addTarget:self action:@selector(onTogglePressed) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_toggleButton];
    }
    return self;
}

- (void)onTogglePressed {
    g_ModieActive = !g_ModieActive;
    if (g_ModieActive) {
        [_toggleButton setTitle:@"MODIE: ON" forState:UIControlStateNormal];
        [_toggleButton setTitleColor:[UIColor systemGreenColor] forState:UIControlStateNormal];
        _toggleButton.layer.borderColor = [UIColor systemGreenColor].CGColor;
    } else {
        [_toggleButton setTitle:@"MODIE: OFF" forState:UIControlStateNormal];
        [_toggleButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        _toggleButton.layer.borderColor = [UIColor systemRedColor].CGColor;
    }
}

// KRİTİK DÜZELTME: Dokunma arkaplana veya view'un kendisine gelirse nil döndür, sadece butona gelirse kabul et
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.superview) {
        return nil;
    }
    return hitView;
}

@end

// Özel Dokunma Geçirgen Pencere Sınıfı
@interface ModieAbsoluteWindow : UIWindow
@end

@implementation ModieAbsoluteWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil; // Boşluklardaki dokunmaları doğrudan oyun penceresine aktar
    }
    return hit;
}
@end

static ModieAbsoluteWindow* g_CheatWindow = nil;

__attribute__((constructor))
static void ModieAbsoluteEntry() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallMetalHook();

        UIWindowScene* targetScene = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                targetScene = (UIWindowScene*)scene;
                break;
            }
        }

        if (targetScene) {
            g_CheatWindow = [[ModieAbsoluteWindow alloc] initWithWindowScene:targetScene];
        } else {
            g_CheatWindow = [[ModieAbsoluteWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        g_CheatWindow.frame = [UIScreen mainScreen].bounds;
        g_CheatWindow.windowLevel = UIWindowLevelAlert + 999;
        g_CheatWindow.backgroundColor = [UIColor clearColor];
        g_CheatWindow.hidden = NO;

        ModieAbsolutePassView* passView = [[ModieAbsolutePassView alloc] initWithFrame:g_CheatWindow.bounds];
        
        UIViewController* dummyVC = [[UIViewController alloc] init];
        dummyVC.view = passView;
        g_CheatWindow.rootViewController = dummyVC;
    });
}
