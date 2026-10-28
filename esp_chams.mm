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

// Global Hile Durumları
static bool g_ToggleChams = true;
static bool g_ToggleNoRecoil = true;
static bool g_ToggleESP = true;

// Metal Chams Hook
static IMP orig_setDepthStencilState = nullptr;
static id<MTLDepthStencilState> g_AlwaysPassDepthState = nil;

void hooked_setDepthStencilState(id self, SEL _cmd, id<MTLDepthStencilState> state) {
    if (g_ToggleChams && state != nil && [self respondsToSelector:@selector(device)]) {
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
// DOKUNMATİK SORUNSULUZ ETKİLEŞİMLİ MENÜ PENCERESİ
// ============================================================================

@interface KanhaTouchPassView : UIView
@property (nonatomic, strong) UIButton* openButton;
@property (nonatomic, strong) UIView* menuPanel;
@end

@implementation KanhaTouchPassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        // 1. Açma / Kapatma Butonu
        _openButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _openButton.frame = CGRectMake(25, 60, 80, 38);
        _openButton.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.9];
        _openButton.layer.cornerRadius = 8.0;
        _openButton.layer.borderWidth = 1.5;
        _openButton.layer.borderColor = [UIColor systemGreenColor].CGColor;
        [_openButton setTitle:@"⚙ MENU" forState:UIControlStateNormal];
        [_openButton setTitleColor:[UIColor systemGreenColor] forState:UIControlStateNormal];
        _openButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [_openButton addTarget:self action:@selector(onMenuButtonClicked) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_openButton];

        // 2. Ana Kontrol Paneli
        _menuPanel = [[UIView alloc] initWithFrame:CGRectMake(25, 110, 240, 210)];
        _menuPanel.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.07 alpha:0.95];
        _menuPanel.layer.cornerRadius = 12.0;
        _menuPanel.layer.borderWidth = 1.5;
        _menuPanel.layer.borderColor = [UIColor systemBlueColor].CGColor;
        _menuPanel.hidden = YES;

        UILabel* titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 12, 210, 20)];
        titleLbl.text = @"⚡ KANHA MOD PANEL";
        titleLbl.textColor = [UIColor whiteColor];
        titleLbl.font = [UIFont boldSystemFontOfSize:13];
        [_menuPanel addSubview:titleLbl];

        // Toggle 1: Chams
        [_menuPanel addSubview:[self createRow:CGRectMake(15, 45, 210, 32) title:@"Chams (Wallhack)" isOn:g_ToggleChams action:@selector(toggleChams:)]];
        // Toggle 2: No Recoil
        [_menuPanel addSubview:[self createRow:CGRectMake(15, 90, 210, 32) title:@"No Recoil" isOn:g_ToggleNoRecoil action:@selector(toggleNoRecoil:)]];
        // Toggle 3: ESP Box
        [_menuPanel addSubview:[self createRow:CGRectMake(15, 135, 210, 32) title:@"ESP Boxes" isOn:g_ToggleESP action:@selector(toggleESP:)]];

        [self addSubview:_menuPanel];
    }
    return self;
}

- (UIView *)createRow:(CGRect)rect title:(NSString *)title isOn:(BOOL)isOn action:(SEL)action {
    UIView* row = [[UIView alloc] initWithFrame:rect];
    
    UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 130, 32)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [row addSubview:lbl];

    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(145, 1, 50, 30)];
    sw.on = isOn;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];

    return row;
}

- (void)onMenuButtonClicked {
    _menuPanel.hidden = !_menuPanel.hidden;
}

- (void)toggleChams:(UISwitch *)sender { g_ToggleChams = sender.isOn; }
- (void)toggleNoRecoil:(UISwitch *)sender { g_ToggleNoRecoil = sender.isOn; }
- (void)toggleESP:(UISwitch *)sender { g_ToggleESP = sender.isOn; }

// Kritik: Sadece menü paneli ve buton açıkken dokunmaları yakala, boşluklarda oyuna geçir
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.isHidden && self.alpha > 0.01) {
        if (!_menuPanel.isHidden && CGRectContainsPoint(_menuPanel.frame, point)) {
            return [_menuPanel hitTest:[self convertPoint:point toView:_menuPanel] withEvent:event];
        }
        if (CGRectContainsPoint(_openButton.frame, point)) {
            return [_openButton hitTest:[self convertPoint:point toView:_openButton] withEvent:event];
        }
    }
    return nil;
}

@end

static UIWindow* g_CheatWindow = nil;

__attribute__((constructor))
static void KanhaTouchEntry() {
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
            g_CheatWindow = [[UIWindow alloc] initWithWindowScene:targetScene];
        } else {
            g_CheatWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        g_CheatWindow.frame = [UIScreen mainScreen].bounds;
        g_CheatWindow.windowLevel = UIWindowLevelAlert + 999; // Oyun motorunun en üst katmanı
        g_CheatWindow.backgroundColor = [UIColor clearColor];
        g_CheatWindow.hidden = NO;

        KanhaTouchPassView* passView = [[KanhaTouchPassView alloc] initWithFrame:g_CheatWindow.bounds];
        
        UIViewController* dummyVC = [[UIViewController alloc] init];
        dummyVC.view = passView;
        g_CheatWindow.rootViewController = dummyVC;
    });
}
