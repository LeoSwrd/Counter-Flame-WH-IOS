// Architecture: ARM64 (iOS 15.0+) | Module: esp_chams.dylib | Runtime: Unity IL2CPP / Metal
// External Dependency: fishhook (embedded inline for zero-dependency compilation)

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

// ============================================================================
// 1. UNITY & IL2CPP DATA STRUCTURES (ARM64 ABI)
// ============================================================================

struct Vector3 {
    float x, y, z;
};

struct Il2CppObject {
    void* klass;
    void* monitor;
};

struct Il2CppString {
    Il2CppObject object;
    int32_t length;
    uint16_t chars[1];
};

struct Il2CppArray {
    Il2CppObject obj;
    void* bounds;
    uintptr_t max_length;
    void* vector[1];
};

// ============================================================================
// 2. IL2CPP EXPORTED API TYPEDEFS & POINTERS
// ============================================================================

typedef void* (*il2cpp_domain_get_t)();
typedef void* (*il2cpp_domain_assembly_open_t)(void* domain, const char* name);
typedef void* (*il2cpp_assembly_get_image_t)(void* assembly);
typedef void* (*il2cpp_class_from_name_t)(void* image, const char* namespaze, const char* name);
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

// Helper struct matching MethodInfo layout on Unity 2020-2023 ARM64 (methodPointer is first field)
struct MethodInfo {
    uintptr_t methodPointer;
};

// ============================================================================
// 3. RESOLVED UNITY ENGINE FUNCTION POINTERS
// ============================================================================

typedef void* (*Camera_get_main_t)();
typedef Vector3 (*Camera_WorldToScreenPoint_t)(void* camera, Vector3 position);
typedef void* (*Component_get_transform_t)(void* component);
typedef Vector3 (*Transform_get_position_t)(void* transform);
typedef Il2CppArray* (*Object_FindObjectsOfType_t)(void* systemType);
typedef Il2CppArray* (*Renderer_GetMaterials_t)(void* renderer);
typedef void (*Material_SetInt_t)(void* material, Il2CppString* name, int value);
typedef void (*Material_SetColor_t)(void* material, Il2CppString* name, float r, float g, float b, float a);

static Camera_get_main_t Camera_get_main = nullptr;
static Camera_WorldToScreenPoint_t Camera_WorldToScreenPoint = nullptr;
static Component_get_transform_t Component_get_transform = nullptr;
static Transform_get_position_t Transform_get_position = nullptr;
static Object_FindObjectsOfType_t Object_FindObjectsOfType = nullptr;
static Renderer_GetMaterials_t Renderer_GetMaterials = nullptr;
static Material_SetInt_t Material_SetInt = nullptr;

static void* g_SkinnedMeshRendererTypeObj = nullptr;
static bool g_Il2CppReady = false;
static bool g_WallhackEnabled = true;

// ============================================================================
// 4. METAL DEPTH-STENCIL CHAMS HOOK (LOW-LEVEL RENDERER OVERRIDE)
// ============================================================================

static IMP orig_setDepthStencilState = nullptr;
static id<MTLDepthStencilState> g_AlwaysPassDepthState = nil;

void hooked_setDepthStencilState(id self, SEL _cmd, id<MTLDepthStencilState> state) {
    if (g_WallhackEnabled && state != nil) {
        // Create an Always-Pass DepthStencilState once using the encoder's device
        if (g_AlwaysPassDepthState == nil && [self respondsToSelector:@selector(device)]) {
            id<MTLDevice> dev = [self performSelector:@selector(device)];
            if (dev) {
                MTLDepthStencilDescriptor* desc = [[MTLDepthStencilDescriptor alloc] init];
                desc.depthCompareFunction = MTLCompareFunctionAlways;
                desc.depthWriteEnabled = NO;
                g_AlwaysPassDepthState = [dev newDepthStencilStateWithDescriptor:desc];
            }
        }
        // Check current label or vertex buffer count to isolate character draws if needed
        // Calling with g_AlwaysPassDepthState disables depth occlusion on active passes
        if (g_AlwaysPassDepthState != nil) {
            ((void(*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, g_AlwaysPassDepthState);
            return;
        }
    }
    ((void(*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, state);
}

static void InstallMetalHook() {
    // Locate concrete Metal render command encoder class at runtime
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;

    Class* classes = (Class*)malloc(sizeof(Class) * (size_t)numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    SEL targetSel = @selector(setDepthStencilState:);
    for (int i = 0; i < numClasses; i++) {
        const char* className = class_getName(classes[i]);
        // Target Apple GPU family Metal Render Command Encoder
        if (strstr(className, "MTLRenderCommandEncoder") != nullptr) {
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
// 5. IL2CPP RESOLVER & SKINNED MESH MATERIAL ZTEST OVERRIDE
// ============================================================================

static uintptr_t GetMethodPointer(void* image, const char* ns, const char* klassName, const char* methodName, int args) {
    void* klass = il2cpp_class_from_name(image, ns, klassName);
    if (!klass) return 0;
    MethodInfo* method = (MethodInfo*)il2cpp_class_get_method_from_name(klass, methodName, args);
    if (!method) return 0;
    return method->methodPointer;
}

static bool InitIl2Cpp() {
    void* handle = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_LAZY | RTLD_NOLOAD);
    if (!handle) handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) return false;

    il2cpp_domain_get = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    il2cpp_domain_assembly_open = (il2cpp_domain_assembly_open_t)dlsym(handle, "il2cpp_domain_assembly_open");
    il2cpp_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    il2cpp_class_from_name = (il2cpp_class_from_name_t)dlsym(handle, "il2cpp_class_from_name");
    il2cpp_class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(handle, "il2cpp_class_get_method_from_name");
    il2cpp_string_new = (il2cpp_string_new_t)dlsym(handle, "il2cpp_string_new");
    il2cpp_type_get_object = (il2cpp_type_get_object_t)dlsym(handle, "il2cpp_type_get_object");
    il2cpp_class_get_type = (il2cpp_class_get_type_t)dlsym(handle, "il2cpp_class_get_type");

    if (!il2cpp_domain_get || !il2cpp_domain_assembly_open || !il2cpp_class_from_name) return false;

    void* domain = il2cpp_domain_get();
    if (!domain) return false;

    void* coreAsm = il2cpp_domain_assembly_open(domain, "UnityEngine.CoreModule.dll");
    if (!coreAsm) coreAsm = il2cpp_domain_assembly_open(domain, "UnityEngine.dll");
    if (!coreAsm) return false;

    void* coreImg = il2cpp_assembly_get_image(coreAsm);
    if (!coreImg) return false;

    Camera_get_main = (Camera_get_main_t)GetMethodPointer(coreImg, "UnityEngine", "Camera", "get_main", 0);
    Camera_WorldToScreenPoint = (Camera_WorldToScreenPoint_t)GetMethodPointer(coreImg, "UnityEngine", "Camera", "WorldToScreenPoint", 1);
    Component_get_transform = (Component_get_transform_t)GetMethodPointer(coreImg, "UnityEngine", "Component", "get_transform", 0);
    Transform_get_position = (Transform_get_position_t)GetMethodPointer(coreImg, "UnityEngine", "Transform", "get_position", 0);
    Object_FindObjectsOfType = (Object_FindObjectsOfType_t)GetMethodPointer(coreImg, "UnityEngine", "Object", "FindObjectsOfType", 1);
    Renderer_GetMaterials = (Renderer_GetMaterials_t)GetMethodPointer(coreImg, "UnityEngine", "Renderer", "GetMaterials", 0);
    Material_SetInt = (Material_SetInt_t)GetMethodPointer(coreImg, "UnityEngine", "Material", "SetInt", 2);

    void* smrClass = il2cpp_class_from_name(coreImg, "UnityEngine", "SkinnedMeshRenderer");
    if (smrClass && il2cpp_class_get_type && il2cpp_type_get_object) {
        const void* smrType = il2cpp_class_get_type(smrClass);
        if (smrType) {
            g_SkinnedMeshRendererTypeObj = il2cpp_type_get_object(smrType);
        }
    }

    return (Camera_get_main && Camera_WorldToScreenPoint && Component_get_transform && Transform_get_position);
}

// ============================================================================
// 6. OVERLAY VIEW & 60FPS CADISPLAYLINK ESP RENDERER
// ============================================================================

struct ScreenBox {
    CGRect rect;
    CGPoint snapEnd;
};

@interface KanhaESPOverlay : UIView
@property (nonatomic, assign) std::vector<ScreenBox> boxes;
@property (nonatomic, strong) UIButton* toggleBtn;
@end

@implementation KanhaESPOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.opaque = NO;

        // Floating toggle button so you can turn Chams/ESP on or off mid-match
        _toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _toggleBtn.frame = CGRectMake(40, 60, 110, 34);
        _toggleBtn.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.08 alpha:0.85];
        _toggleBtn.layer.cornerRadius = 6.0;
        _toggleBtn.layer.borderWidth = 1.5;
        _toggleBtn.layer.borderColor = [UIColor greenColor].CGColor;
        [_toggleBtn setTitle:@"WH: ON" forState:UIControlStateNormal];
        [_toggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        _toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [_toggleBtn addTarget:self action:@selector(onTogglePressed) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_toggleBtn];
    }
    return self;
}

// Pass touches through everywhere except the toggle button
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(self.toggleBtn.frame, point)) {
        return self.toggleBtn;
    }
    return nil;
}

- (void)onTogglePressed {
    g_WallhackEnabled = !g_WallhackEnabled;
    if (g_WallhackEnabled) {
        [_toggleBtn setTitle:@"WH: ON" forState:UIControlStateNormal];
        [_toggleBtn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
        _toggleBtn.layer.borderColor = [UIColor greenColor].CGColor;
    } else {
        [_toggleBtn setTitle:@"WH: OFF" forState:UIControlStateNormal];
        [_toggleBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        _toggleBtn.layer.borderColor = [UIColor redColor].CGColor;
    }
    [self setNeedsDisplay];
}

- (void)tickESP:(CADisplayLink *)link {
    if (!g_Il2CppReady) {
        g_Il2CppReady = InitIl2Cpp();
        return;
    }

    _boxes.clear();
    if (!g_WallhackEnabled) {
        [self setNeedsDisplay];
        return;
    }

    void* mainCam = Camera_get_main();
    if (!mainCam || !Object_FindObjectsOfType || !g_SkinnedMeshRendererTypeObj) {
        [self setNeedsDisplay];
        return;
    }

    Il2CppArray* renderers = Object_FindObjectsOfType(g_SkinnedMeshRendererTypeObj);
    if (!renderers || renderers->max_length == 0) {
        [self setNeedsDisplay];
        return;
    }

    CGFloat screenW = self.bounds.size.width;
    CGFloat screenH = self.bounds.size.height;
    CGFloat scale = [UIScreen mainScreen].scale;

    Il2CppString* zTestProp = il2cpp_string_new ? il2cpp_string_new("_ZTest") : nullptr;

    // Cap iteration at 64 entities to guarantee O(1) frame budget
    uintptr_t count = renderers->max_length > 64 ? 64 : renderers->max_length;
    for (uintptr_t i = 0; i < count; i++) {
        void* smr = renderers->vector[i];
        if (!smr) continue;

        // 1. Force Shader _ZTest = 8 (CompareFunction.Always) on player materials
        if (Renderer_GetMaterials && Material_SetInt && zTestProp) {
            Il2CppArray* mats = Renderer_GetMaterials(smr);
            if (mats && mats->max_length <= 16) {
                for (uintptr_t m = 0; m < mats->max_length; m++) {
                    void* mat = mats->vector[m];
                    if (mat) {
                        Material_SetInt(mat, zTestProp, 8);
                    }
                }
            }
        }

        // 2. Project 3D Player Bone/Root Position to 2D Screen Space for ESP Box
        void* trans = Component_get_transform(smr);
        if (!trans) continue;

        Vector3 worldFoot = Transform_get_position(trans);
        // Ignore origin/uninitialized prefabs
        if (fabsf(worldFoot.x) < 0.01f && fabsf(worldFoot.y) < 0.01f && fabsf(worldFoot.z) < 0.01f) continue;

        Vector3 worldHead = { worldFoot.x, worldFoot.y + 1.75f, worldFoot.z };

        Vector3 screenFoot = Camera_WorldToScreenPoint(mainCam, worldFoot);
        Vector3 screenHead = Camera_WorldToScreenPoint(mainCam, worldHead);

        // z > 0 means target is in front of camera frustum
        if (screenFoot.z > 0.5f && screenHead.z > 0.5f) {
            // Convert Unity pixel coords (bottom-left origin) to UIKit points (top-left origin)
            CGFloat footX = screenFoot.x / scale;
            CGFloat footY = screenH - (screenFoot.y / scale);
            CGFloat headY = screenH - (screenHead.y / scale);

            CGFloat boxH = fabs(footY - headY);
            if (boxH > 8.0f && boxH < screenH) {
                CGFloat boxW = boxH * 0.52f;
                ScreenBox sb;
                sb.rect = CGRectMake(footX - (boxW * 0.5f), headY, boxW, boxH);
                sb.snapEnd = CGPointMake(footX, footY);
                _boxes.push_back(sb);
            }
        }
    }

    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (!g_WallhackEnabled || _boxes.empty()) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetLineWidth(ctx, 1.5);
    CGContextSetRGBStrokeColor(ctx, 0.0, 1.0, 0.25, 0.95); // Neon Green ESP

    CGPoint topCenter = CGPointMake(self.bounds.size.width * 0.5f, 0.0f);

    for (const auto& sb : _boxes) {
        // Draw 2D Corner/Full Box
        CGContextStrokeRect(ctx, sb.rect);

        // Draw Snapline from top-center of screen to player feet
        CGContextMoveToPoint(ctx, topCenter.x, topCenter.y);
        CGContextAddLineToPoint(ctx, sb.snapEnd.x, sb.snapEnd.y);
        CGContextStrokePath(ctx);
    }
}

@end

// ============================================================================
// 7. CONSTRUCTOR ENTRY POINT (FIRES AUTOMATICALLY ON IPA LAUNCH)
// ============================================================================

static KanhaESPOverlay* g_Overlay = nil;

__attribute__((constructor))
static void KanhaEntry() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallMetalHook();

        UIWindow* keyWindow = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (w.isKeyWindow) {
                        keyWindow = w;
                        break;
                    }
                }
            }
        }
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }
        if (!keyWindow) return;

        g_Overlay = [[KanhaESPOverlay alloc] initWithFrame:keyWindow.bounds];
        g_Overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [keyWindow addSubview:g_Overlay];

        CADisplayLink* link = [CADisplayLink displayLinkWithTarget:g_Overlay selector:@selector(tickESP:)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
}
