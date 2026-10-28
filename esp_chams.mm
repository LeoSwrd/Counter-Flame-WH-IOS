#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#include <vector>
#include <cmath>

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

// Unity API Pointerları
typedef void* (*Camera_get_main_t)();
typedef Vector3 (*Camera_WorldToScreenPoint_t)(void* camera, Vector3 position);
typedef void* (*Component_get_transform_t)(void* component);
typedef Vector3 (*Transform_get_position_t)(void* transform);
typedef void* (*Object_FindObjectsOfType_t)(void* systemType);
typedef void* (*Renderer_GetMaterials_t)(void* renderer);
typedef void (*Material_SetInt_t)(void* material, Il2CppString* name, int value);

static Camera_get_main_t Camera_get_main = nullptr;
static Camera_WorldToScreenPoint_t Camera_WorldToScreenPoint = nullptr;
static Component_get_transform_t Component_get_transform = nullptr;
static Transform_get_position_t Transform_get_position = nullptr;
static Object_FindObjectsOfType_t Object_FindObjectsOfType = nullptr;
static Renderer_GetMaterials_t Renderer_GetMaterials = nullptr;
static Material_SetInt_t Material_SetInt = nullptr;

static void* g_RendererTypeObj = nullptr;
static bool g_ModieActive = true;
static bool g_Il2CppReady = false;

static void InitIl2CppAPI() {
    if (g_Il2CppReady) return;
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

    Camera_get_main = (Camera_get_main_t)GetMethodPointer(coreImg, "UnityEngine", "Camera", "get_main", 0);
    Camera_WorldToScreenPoint = (Camera_WorldToScreenPoint_t)GetMethodPointer(coreImg, "UnityEngine", "Camera", "WorldToScreenPoint", 1);
    Component_get_transform = (Component_get_transform_t)GetMethodPointer(coreImg, "UnityEngine", "Component", "get_transform", 0);
    Transform_get_position = (Transform_get_position_t)GetMethodPointer(coreImg, "UnityEngine", "Transform", "get_position", 0);
    Object_FindObjectsOfType = (Object_FindObjectsOfType_t)GetMethodPointer(coreImg, "UnityEngine", "Object", "FindObjectsOfType", 1);
    Renderer_GetMaterials = (Renderer_GetMaterials_t)GetMethodPointer(coreImg, "UnityEngine", "Renderer", "GetMaterials", 0);
    Material_SetInt = (Material_SetInt_t)GetMethodPointer(coreImg, "UnityEngine", "Material", "SetInt", 2);

    void* rendClass = il2cpp_class_from_name(coreImg, "UnityEngine", "Renderer");
    if (rendClass && il2cpp_class_get_type && il2cpp_type_get_object) {
        const void* rendType = il2cpp_class_get_type(rendClass);
        if (rendType) g_RendererTypeObj = il2cpp_type_get_object(rendType);
    }

    if (Camera_get_main && Object_FindObjectsOfType && Renderer_GetMaterials) {
        g_Il2CppReady = true;
    }
}

// ESP Kutuları Görsel Çizici
struct BoxEntity {
    CGRect rect;
    CGPoint foot;
};

@interface ModieOverlayView : UIView
@property (nonatomic, assign) std::vector<BoxEntity> entities;
@end

@implementation ModieOverlayView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    if (!g_ModieActive || _entities.empty()) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetLineWidth(ctx, 1.5);
    CGContextSetRGBStrokeColor(ctx, 0.0, 1.0, 0.3, 0.95);

    for (const auto& item : _entities) {
        CGContextStrokeRect(ctx, item.rect);
        CGContextMoveToPoint(ctx, self.bounds.size.width * 0.5f, 0.0f);
        CGContextAddLineToPoint(ctx, item.foot.x, item.foot.y);
        CGContextStrokePath(ctx);
    }
}
@end

// Oyun Döngüsü
@interface ModieGameCore : NSObject
@property (nonatomic, strong) ModieOverlayView* overlay;
@end

@implementation ModieGameCore
- (void)gameLoop:(CADisplayLink *)link {
    if (!g_ModieActive) {
        if (_overlay) _overlay.hidden = YES;
        return;
    }
    if (_overlay) _overlay.hidden = NO;

    if (!g_Il2CppReady) {
        InitIl2CppAPI();
        return;
    }

    void* mainCam = Camera_get_main();
    if (!mainCam || !Object_FindObjectsOfType || !g_RendererTypeObj) return;

    Il2CppString* zProp = il2cpp_string_new ? il2cpp_string_new("_ZTest") : nullptr;
    Il2CppArray* renderers = (Il2CppArray*)Object_FindObjectsOfType(g_RendererTypeObj);
    if (!renderers) return;

    std::vector<BoxEntity> boxes;
    CGFloat screenH = _overlay.bounds.size.height;
    CGFloat scale = [UIScreen mainScreen].scale;

    uintptr_t maxCount = renderers->max_length > 60 ? 60 : renderers->max_length;
    for (uintptr_t i = 0; i < maxCount; i++) {
        void* rend = renderers->vector[i];
        if (!rend) continue;

        if (Renderer_GetMaterials && Material_SetInt && zProp) {
            Il2CppArray* mats = (Il2CppArray*)Renderer_GetMaterials(rend);
            if (mats && mats->max_length <= 16) {
                for (uintptr_t m = 0; m < mats->max_length; m++) {
                    void* mat = mats->vector[m];
                    if (mat) Material_SetInt((void*)mat, zProp, 8);
                }
            }
        }

        void* trans = Component_get_transform(rend);
        if (!trans) continue;
        Vector3 pos = Transform_get_position(trans);
        if (std::abs(pos.x) < 0.01f && std::abs(pos.y) < 0.01f) continue;

        Vector3 headPos = { pos.x, pos.y + 1.8f, pos.z };
        Vector3 sFoot = Camera_WorldToScreenPoint(mainCam, pos);
        Vector3 sHead = Camera_WorldToScreenPoint(mainCam, headPos);

        if (sFoot.z > 0.1f && sHead.z > 0.1f) {
            CGFloat fx = sFoot.x / scale;
            CGFloat fy = screenH - (sFoot.y / scale);
            CGFloat hy = screenH - (sHead.y / scale);
            CGFloat h = std::abs(fy - hy);
            CGFloat w = h * 0.5f;

            if (h > 10.0f && h < screenH) {
                BoxEntity ent;
                ent.rect = CGRectMake(fx - (w * 0.5f), hy, w, h);
                ent.foot = CGPointMake(fx, fy);
                boxes.push_back(ent);
            }
        }
    }

    _overlay.entities = boxes;
    [_overlay setNeedsDisplay];
}
@end

// Tek Tuş Arayüzü
@interface ModieControlView : UIView
@property (nonatomic, strong) UIButton* toggleButton;
@end

@implementation ModieControlView
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
        [_toggleButton addTarget:self action:@selector(onToggle) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_toggleButton];
    }
    return self;
}

- (void)onToggle {
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

@interface ModieSafeWindow : UIWindow
@end

@implementation ModieSafeWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView* hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static ModieSafeWindow* g_Window = nil;
static ModieGameCore* g_Core = nil;

__attribute__((constructor))
static void ModieUltimateEntry() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIScene* targetScene = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                targetScene = scene;
                break;
            }
        }

        if (targetScene && [targetScene isKindOfClass:[UIWindowScene class]]) {
            g_Window = [[ModieSafeWindow alloc] initWithWindowScene:(UIWindowScene*)targetScene];
        } else {
            g_Window = [[ModieSafeWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        g_Window.frame = [UIScreen mainScreen].bounds;
        g_Window.windowLevel = UIWindowLevelAlert + 999;
        g_Window.backgroundColor = [UIColor clearColor];
        g_Window.hidden = NO;

        ModieOverlayView* overlay = [[ModieOverlayView alloc] initWithFrame:g_Window.bounds];
        ModieControlView* control = [[ModieControlView alloc] initWithFrame:g_Window.bounds];
        [control addSubview:overlay];

        UIViewController* vc = [[UIViewController alloc] init];
        vc.view = control;
        g_Window.rootViewController = vc;

        g_Core = [[ModieGameCore alloc] init];
        g_Core.overlay = overlay;

        CADisplayLink* link = [CADisplayLink displayLinkWithTarget:g_Core selector:@selector(gameLoop:)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
}
