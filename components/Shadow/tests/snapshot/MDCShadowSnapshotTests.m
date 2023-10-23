// Copyright 2019-present the Material Components for iOS authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <QuartzCore/QuartzCore.h>

#import "MDCAvailability.h"
#import "MDCShadow.h"
#import "MDCShadowsCollection.h"
#import "MDCSnapshotTestCase.h"
#import "UIView+MDCSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Returns a dynamic color which is green in light mode and red in dark mode.
 */
static UIColor *MDCTestDynamicShadowColor(void) {
#if MDC_AVAILABLE_SDK_IOS(13_0)
  if (@available(iOS 13.0, *)) {
    return [UIColor colorWithDynamicProvider:^(UITraitCollection *traitCollection) {
      switch (traitCollection.userInterfaceStyle) {
        case UIUserInterfaceStyleUnspecified:
          __attribute__((fallthrough));
        case UIUserInterfaceStyleLight:
          return UIColor.greenColor;
        case UIUserInterfaceStyleDark:
          return UIColor.redColor;
      }
      __builtin_unreachable();
    }];
  }
#endif  // MDC_AVAILABLE_SDK_IOS(13_0)
  // Should not be reached (do not invoke this function on iOS < 13).
  abort();
}

/**
 A UIView that supports rendering a shadow and overriding its traitCollection.
 */
@interface MDCShadowTestView : UIView
@property(nonatomic) CGFloat shadowElevation;
@property(nonatomic) MDCShadow *customShadow;
@property(nonatomic, strong, nonnull) UIColor *customShadowColor;
@property(nonatomic, strong, nullable) CAShapeLayer *shapeLayer;
@property(nonatomic, nullable) CGPathRef shapePath;
@property(nonatomic, strong, nullable) UITraitCollection *traitCollectionOverride;

@end

@implementation MDCShadowTestView

@synthesize shapePath = _shapePath;

- (UITraitCollection *)traitCollection {
  return self.traitCollectionOverride ?: [super traitCollection];
}

- (void)layoutSubviews {
  [super layoutSubviews];

  if (self.shapePath != nil) {
    _Nonnull CGPathRef shapePath = self.shapePath;
    self.backgroundColor = nil;
    MDCConfigureShadowForViewWithPath(
        self, [MDCShadowsCollectionDefault() shadowForElevation:self.shadowElevation], shapePath);
  } else if (self.customShadow != nil) {
    self.backgroundColor = UIColor.whiteColor;
    MDCConfigureShadowForView(self, self.customShadow);
  } else if (self.customShadowColor != nil) {
    self.backgroundColor = UIColor.whiteColor;
    MDCShadow *shadow = [MDCShadowsCollectionDefault() shadowForElevation:self.shadowElevation];
    shadow = [[MDCShadowBuilder builderWithColor:self.customShadowColor
                                         opacity:shadow.opacity
                                          radius:shadow.radius
                                          offset:shadow.offset
                                          spread:shadow.spread] build];
    MDCConfigureShadowForView(self, shadow);
  } else {
    self.backgroundColor = UIColor.whiteColor;
    MDCConfigureShadowForView(
        self, [MDCShadowsCollectionDefault() shadowForElevation:self.shadowElevation]);
  }
}

- (void)setShapePath:(CGPathRef _Nullable)shapePath {
  if (_shapeLayer) {
    [_shapeLayer removeFromSuperlayer];
    _shapeLayer = nil;
  }
  if (shapePath) {
    // Note we cannot use self.layer.mask here, as it would mask the shadow.
    CAShapeLayer *shapeLayer = CAShapeLayer.layer;
    shapeLayer.fillColor = UIColor.whiteColor.CGColor;
    shapeLayer.path = shapePath;
    [self.layer addSublayer:shapeLayer];
  }
  _shapePath = shapePath;
}

@end

/**
 Snapshot tests for MDCShadow functions.
 */
@interface MDCShadowSnapshotTests : MDCSnapshotTestCase

@property(nonatomic, strong) MDCShadowTestView *view;

@end

@implementation MDCShadowSnapshotTests

- (void)setUp {
  [super setUp];
  self.view = [[MDCShadowTestView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
}

#pragma mark - Helpers

- (void)generateSnapshotAndVerifyForView:(UIView *)view {
  UIView *snapshotView = [view mdc_addToBackgroundView];
  [self snapshotVerifyView:snapshotView];
}

- (void)generateSnapshotForIOS13AndVerifyForView:(UIView *)view {
  UIView *snapshotView = [view mdc_addToBackgroundView];
  [self snapshotVerifyViewForIOS13:snapshotView];
}

#pragma mark - Tests

- (void)testShadowWithZeroElevationShouldNotRenderShadow {
  // Given
  self.view.shadowElevation = 0;

  // Then
  [self generateSnapshotAndVerifyForView:self.view];
}

- (void)testShadowWithLowElevationShouldRenderShadow {
  // Given
  self.view.shadowElevation = 1;

  // Then
  [self generateSnapshotAndVerifyForView:self.view];
}

- (void)testShadowWithHighElevationShouldRenderShadow {
  // Given
  self.view.shadowElevation = 8;

  // Then
  [self generateSnapshotAndVerifyForView:self.view];
}

- (void)testShadowWithLowElevationShouldUpdateShadowOnBoundsChange {
  // Given
  self.view.shadowElevation = 1;

  // When
  [self.view layoutIfNeeded];
  self.view.bounds = CGRectMake(0, 0, 180, 20);

  // Then
  [self generateSnapshotAndVerifyForView:self.view];
}

- (void)testShadowWithLowElevationAndCornerRadiusShouldRenderRoundedShadow {
  // Given
  self.view.shadowElevation = 1;
  self.view.layer.cornerRadius = 3;

  // Then
  [self generateSnapshotAndVerifyForView:self.view];
}

- (void)testShadowWithLowElevationAndCornerRadiusShouldUpdateShadowOnBoundsChange {
  // Given
  self.view.shadowElevation = 1;
  self.view.layer.cornerRadius = 3;

  // When
  [self.view layoutIfNeeded];
  self.view.bounds = CGRectMake(0, 0, 180, 20);

  // Then
  [self generateSnapshotAndVerifyForView:self.view];
}

- (void)testShadowWithLowElevationAndShapeLayerShouldRenderShapedShadow {
  // Given
  self.view.shadowElevation = 1;
  UIBezierPath *triangleBezierPath = UIBezierPath.bezierPath;
  [triangleBezierPath moveToPoint:CGPointMake(40, 0)];
  [triangleBezierPath addLineToPoint:CGPointMake(80, 80)];
  [triangleBezierPath addLineToPoint:CGPointMake(0, 80)];
  [triangleBezierPath closePath];
  self.view.shapePath = triangleBezierPath.CGPath;

  // Then
  [self generateSnapshotAndVerifyForView:self.view];
}

- (void)testCustomShadowColorInLightModeShouldBeGreen {
#if MDC_AVAILABLE_SDK_IOS(13_0)
  if (@available(iOS 13.0, *)) {
    // Given
    self.view.shadowElevation = 1;
    self.view.customShadowColor = MDCTestDynamicShadowColor();

    // When
    self.view.traitCollectionOverride =
        [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];

    // Then
    [self generateSnapshotForIOS13AndVerifyForView:self.view];
  }
#endif  // MDC_AVAILABLE_SDK_IOS(13_0)
}

- (void)testCustomShadowColorInDarkModeShouldBeRed {
#if MDC_AVAILABLE_SDK_IOS(13_0)
  if (@available(iOS 13.0, *)) {
    // Given
    self.view.shadowElevation = 1;
    self.view.customShadowColor = MDCTestDynamicShadowColor();

    // When
    self.view.traitCollectionOverride =
        [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];

    // Then
    [self generateSnapshotForIOS13AndVerifyForView:self.view];
  }
#endif  // MDC_AVAILABLE_SDK_IOS(13_0)
}

- (void)testCustomShadowSpread {
  // When
  self.view.customShadow = [[MDCShadowBuilder builderWithColor:MDCShadowColor()
                                                       opacity:0.2
                                                        radius:2.5
                                                        offset:CGSizeMake(0, 2)
                                                        spread:0.45] build];

  // Then
  [self generateSnapshotForIOS13AndVerifyForView:self.view];
}

@end

NS_ASSUME_NONNULL_END
