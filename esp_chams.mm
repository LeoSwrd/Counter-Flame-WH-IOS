#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

// Global Hile Durumu
static bool g_ModieActive = true;

// Metal DepthStencil Hook (Duvar Arkası / Chams için en stabil yöntem)
static IMP orig_setDepthStencilState = nil;
static id<MTLDepthStencilState> g_AlwaysPassState = nil;

void hooked_setDepthStencilState(id self, SEL _cmd, id<MTLDepthStencilState> state) {
    if (g_ModieActive && state != nil && [self respondsToSelector:@selector(device)]) {
        if (g_AlwaysPassState == nil) {
            id<MTLDevice> dev = [self performSelector:@selector(device)];
            if (dev) {
                MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
                desc.depthCompareFunction = MTLCompareFunctionAlways;
                desc.depthWriteEnabled = NO;
                g_AlwaysPassState = [dev newDepthStencilStateWithDescriptor:desc];
            }
        }
        if (g_AlwaysPassState != nil) {
            ((void(*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, g_AlwaysPassState);
            return;
        }
    }
    ((void(*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, state);
}

static void InstallMetalHook() {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    SEL targetSel = @selector(setDepthStencilState:);
    for (int i = 0; i < numClasses; i++) {
        if (strstr(class_getName(classes[i]), "MTLRenderCommandEncoder") != nil) {
            Method m = class_getInstanceMethod(classes[i], targetSel);
            if (m != nil) {
                orig_setDepthStencilState = method_setImplementation(m, (IMP)hooked_setDepthStencilState);
                break;
            }
        }
    }
    free(classes);
}

// Tek Tuş Görünümü
@interface ModieCleanButtonView : UIView
@property (nonatomic, strong) UIButton *toggleButton;
@end

@implementation ModieCleanButtonView

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

@interface ModieCleanWindow : UIWindow
@end

@implementation ModieCleanWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}
@end

static ModieCleanWindow *g_CheatWindow = nil;

__attribute__((constructor))
static void ModieCleanEntry() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        InstallMetalHook();

        UIWindowScene *targetScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                targetScene = (UIWindowScene *)scene;
                break;
            }
        }

        if (targetScene) {
            g_CheatWindow = [[ModieCleanWindow alloc] initWithWindowScene:targetScene];
        } else {
            g_CheatWindow = [[ModieCleanWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        g_CheatWindow.frame = [UIScreen mainScreen].bounds;
        g_CheatWindow.windowLevel = UIWindowLevelAlert + 999;
        g_CheatWindow.backgroundColor = [UIColor clearColor];
        g_CheatWindow.hidden = NO;

        ModieCleanButtonView *cleanView = [[ModieCleanButtonView alloc] initWithFrame:g_CheatWindow.bounds];
        UIViewController *dummyVC = [[UIViewController alloc] init];
        dummyVC.view = cleanView;
        g_CheatWindow.rootViewController = dummyVC;
    });
}
