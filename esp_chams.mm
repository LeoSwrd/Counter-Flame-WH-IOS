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

struct Il2CppObject { void* klass; void* monitor; };
struct Il2CppString { Il2CppObject object; int32_t length; uint16_t chars[1]; };
struct Il2CppArray { Il2CppObject obj; void* bounds; uintptr_t max_length; void* vector[1]; };

typedef void* (*il2cpp_domain_get_t)();
typedef void* (*il2cpp_domain_assembly_open_t)(void* domain, const char* name);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef void* (*il2cpp_class_from_name_t)(void* image, const char* ns, const char* name);
typedef void* (*il2cpp_class_get_method_from_name_t)(void* klass, const char* name, int argsCount);
typedef Il2CppString* (*il2cpp_string_new_t)(const char* str);
typedef void* (*il2cpp_type_get_object_t)(const void* type);
typedef const void* (*il2cpp_class_get_type_t)(void* klass);

static il2cpp_domain_get_t il2cpp_domain_get = nullptr;
static il2cpp_domain_assembly_open_t il2cpp_domain_assembly_open = nullptr;
static il2cpp_assembly_get_image_t il2cpp_assembly_get_image = nullptr;
static il2cpp_class_from_name_t il2cpp_class_from_name = nullptr;
static il2cpp_class_get_method_from_name_t il2cpp_class_get_method_from_name = nullptr;
static il2cpp_string_new_t il2cpp_string_new = nullptr;
static il2cpp_type_get_object_t il2cpp_type_get_object = nullptr;
static il2cpp_class_get_type_t il2cpp_class_get_type = nullptr;

struct MethodInfo { uintptr_t methodPointer; };

static uintptr_t GetMethodPointer(void* image, const char* ns, const char* klassName, const char* methodName, int args) {
    void* klass = il2cpp_class_from_name(image, ns, klassName);
    if (!klass) return 0;
    MethodInfo* method = (MethodInfo*)il2cpp_class_get_method_from_name(klass, methodName, args);
    if (!method) return 0;
    return method->methodPointer;
}

// Unity Fonksiyon Pointerları
typedef void* (*Object_FindObjectsOfType_t)(void* systemType);
typedef Il2CppArray* (*Renderer_GetMaterials_t)(void* renderer);
typedef void (*Material_SetInt_t)(void* material, Il2CppString* name, int value);

static Object_FindObjectsOfType_t Object_FindObjectsOfType = nullptr;
static Renderer_GetMaterials_t Renderer_GetMaterials = nullptr;
static Material_SetInt_t Material_SetInt = nullptr;

static void* g_RendererTypeObj = nullptr;
static bool g_ModieActive = true;
static bool g_Il2CppResolved = false;

static void ResolveIl2CppFunctions() {
    if (g_Il2CppResolved) return;
    void* handle = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_LAZY | RTLD_NOLOAD);
    if (!handle) handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) return;

    il2cpp_domain_get = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    il2cpp_domain_assembly_open = (il2cpp_domain_assembly_open_t)dlsym(handle, "il2cpp_domain_assembly_open");
    il2cpp_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    il2cpp_class_from_name = (il2cpp_class_from_name_t)dlsym(handle, "il2cpp_class_from_name");
    il2cpp_class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(handle, "il2cpp_class_get_method_from_name");
    il2cpp_string_new = (il2cpp_string_new_t)dlsym(handle, "il2cpp_string_new");
    il2cpp_type_get_object = (il2cpp_type_get_object_t)dlsym(handle, "il2cpp_type_get_object");
    il2cpp_class_get_type = (il2cpp_class_get_type_t)dlsym(handle, "il2cpp_class_get_type");

    if (!il2cpp_domain_get || !il2cpp_class_from_name) return;

    void* domain = il2cpp_domain_get();
    if (!domain) return;
    void* coreAsm = il2cpp_domain_assembly_open(domain, "UnityEngine.CoreModule.dll");
    if (!coreAsm) coreAsm = il2cpp_domain_assembly_open(domain, "UnityEngine.dll");
    if (!coreAsm) return;
    void* coreImg = il2cpp_assembly_get_image(coreAsm);
    if (!coreImg) return;

    Object_FindObjectsOfType = (Object_FindObjectsOfType_t)GetMethodPointer(coreImg, "UnityEngine", "Object", "FindObjectsOfType", 1);
    Renderer_GetMaterials = (Renderer_GetMaterials_t)GetMethodPointer(coreImg, "UnityEngine", "Renderer", "GetMaterials", 0);
    Material_SetInt = (Material_SetInt_t)GetMethodPointer(coreImg, "UnityEngine", "Material", "SetInt", 2);

    void* rendClass = il2cpp_class_from_name(coreImg, "UnityEngine", "Renderer");
    if (rendClass && il2cpp_class_get_type && il2cpp_type_get_object) {
        const void* rendType = il2cpp_class_get_type(rendClass);
        if (rendType) {
            g_RendererTypeObj = il2cpp_type_get_object(rendType);
        }
    }

    if (Object_FindObjectsOfType && Renderer_GetMaterials && Material_SetInt) {
        g_Il2CppResolved = true;
    }
}

// ============================================================================
// HİLE DÖNGÜSÜ (CADISPLAYLINK İLE HER FRAME ÇALIŞIR)
// ============================================================================

@interface ModieCheatLoop : NSObject
@end

@implementation ModieCheatLoop
- (void)frameTick:(CADisplayLink *)link {
    if (!g_ModieActive) return;
    
    if (!g_Il2CppResolved) {
        ResolveIl2CppFunctions();
        return;
    }

    if (!Object_FindObjectsOfType || !g_RendererTypeObj || !Renderer_GetMaterials || !Material_SetInt) return;

    Il2CppString* zTestProp = il2cpp_string_new ? il2cpp_string_new("_ZTest") : nullptr;
    if (!zTestProp) return;

    // Sahnedeki tüm Renderer nesnelerini çek (Karakterler dahil)
    Il2CppArray* renderers = Object_FindObjectsOfType(g_RendererTypeObj);
    if (!renderers || renderers->max_length == 0) return;

    uintptr_t limit = renderers->max_length > 48 ? 48 : renderers->max_length;
    for (uintptr_t i = 0; i < limit; i++) {
        void* rend = renderers->vector[i];
        if (!rend) continue;

        // Materyallerin ZTest değerini 8 (Always) yaparak duvar arkasında görünür kıl (Chams)
        Il2CppArray* mats = Renderer_GetMaterials(rend);
        if (mats && mats->max_length <= 12) {
            for (uintptr_t m = 0; m < mats->max_length; m++) {
                void* mat = mats->vector[m];
                if (mat) {
                    Material_SetInt(mat, zTestProp, 8);
                }
            }
        }
    }
}
@end

// ============================================================================
// TEK TUŞ ARAYÜZÜ
// ============================================================================

@interface ModieSingleButtonView : UIView
@property (nonatomic, strong) UIButton* toggleButton;
@end

@implementation ModieSingleButtonView

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

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.isHidden && CGRectContainsPoint(_toggleButton.frame, point)) {
        return [_toggleButton hitTest:[self convertPoint:point toView:_toggleButton] withEvent:event];
    }
    return nil;
}

@end

@interface ModieWindow : UIWindow
@end

@implementation ModieWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}
@end

static ModieWindow* g_CheatWindow = nil;
static ModieCheatLoop* g_CheatLoopObj = nil;

__attribute__((constructor))
static void ModieDirectEntry() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindowScene* targetScene = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                targetScene = (UIWindowScene*)scene;
                break;
            }
        }

        if (targetScene) {
            g_CheatWindow = [[ModieWindow alloc] initWithWindowScene:targetScene];
        } else {
            g_CheatWindow = [[ModieWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        g_CheatWindow.frame = [UIScreen mainScreen].bounds;
        g_CheatWindow.windowLevel = UIWindowLevelAlert + 999;
        g_CheatWindow.backgroundColor = [UIColor clearColor];
        g_CheatWindow.hidden = NO;

        ModieSingleButtonView* singleView = [[ModieSingleButtonView alloc] initWithFrame:g_CheatWindow.bounds];
        UIViewController* dummyVC = [[UIViewController alloc] init];
        dummyVC.view = singleView;
        g_CheatWindow.rootViewController = dummyVC;

        g_CheatLoopObj = [[ModieCheatLoop alloc] init];
        CADisplayLink* link = [CADisplayLink displayLinkWithTarget:g_CheatLoopObj selector:@selector(frameTick:)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
}
