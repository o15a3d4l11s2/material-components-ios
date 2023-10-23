// Copyright 2018-present the Material Components for iOS authors. All Rights Reserved.
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

#import "MDCBottomNavigationBarController.h"

#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprivate-header"
#import "MDCBottomNavigationBar+Private.h"
#import "MDCBottomNavigationLargeItemDialogView.h"
#pragma clang diagnostic pop
#import "MDCBottomNavigationBar.h"
#import "MDCBottomNavigationBarControllerDelegate.h"

NS_ASSUME_NONNULL_BEGIN

// A context for Key Value Observing
static void *const kObservationContext = (void *)&kObservationContext;
static const CGFloat kLargeItemViewHeight = 210;
static const CGFloat kLargeItemViewWidth = 210;
static const NSTimeInterval kLargeItemViewAnimationDuration = 0.1;
static const NSTimeInterval kLongPressMinimumPressDuration = 0.2;
static const NSTimeInterval kNavigationBarHideShowAnimationDuration = 0.1;
static const NSUInteger kLongPressNumberOfTouchesRequired = 1;
static NSString *const kSelectedViewControllerRestorationKey = @"selectedViewController";

/**
 The transform of the large item view when it is in a transitional state (appearing or
 dismissing).
 */
static CGAffineTransform LargeItemViewAnimationTransitionTransform(void) {
  return CGAffineTransformScale(CGAffineTransformIdentity, (CGFloat)0.97, (CGFloat)0.97);
}

/**
 Decodes a view controller with the given key from the given coder. If the coder does not have an
 object associated with the key or the value is not a @c UIViewController this function returns nil.
 */
static UIViewController *_Nullable DecodeViewController(NSCoder *coder, NSString *key) {
  if (![coder containsValueForKey:key]) {
    return nil;
  }

  UIViewController *viewController = [coder decodeObjectForKey:key];
  if ([viewController isKindOfClass:[UIViewController class]]) {
    return viewController;
  }

  return nil;
}

@interface MDCBottomNavigationBarController ()

/** The view that hosts the content for the selected view controller. */
@property(nonatomic, strong) UIView *content;

/** The gesture recognizer for detecting long presses on tab bar items. */
@property(nonatomic, strong, nonnull)
    UILongPressGestureRecognizer *navigationBarLongPressRecognizer;

/** The dialog view to display a large item view. */
@property(nonatomic, strong, nullable) MDCBottomNavigationLargeItemDialogView *largeItemDialog;

/** Returns if the long press gesture recognizer has been added to the navigation bar. */
@property(nonatomic, readonly, getter=isNavigationBarLongPressRecognizerRegistered)
    BOOL navigationBarLongPressRecognizerRegistered;

/**
 Indicates if the large item view is in the process of dismissing. This is to ensure that the dialog
 animation is not started again if it is already animating a dismissal.
 */
@property(nonatomic, getter=isDismissingLargeItemDialog) BOOL dismissingLargeItemView;

/** The constraint between the bottom of @c navigationBar and its superview. */
@property(nonatomic, strong, nullable) NSLayoutConstraint *navigationBarBottomAnchorConstraint;

/** The constraint between @c navigationBar.barItemsBottomAnchor and the bottom of the safe area. */
@property(nonatomic, strong, nullable) NSLayoutConstraint *navigationBarItemsBottomAnchorConstraint;

/** The constraints for the @c navigationBar in a vertical layout. */
@property(nonatomic, strong, nonnull)
    NSMutableArray<NSLayoutConstraint *> *navigationBarVerticalLayoutConstraints;

/** The constraint between the leading edge of @c navigationBar and its superview. */
@property(nonatomic, strong, nullable) NSLayoutConstraint *navigationBarLeadingAnchorConstraint;

/** The constraints for the @c navigationBar in a horizontal layout. */
@property(nonatomic, strong, nonnull)
    NSMutableArray<NSLayoutConstraint *> *navigationBarHorizontalLayoutConstraints;

/** The constraint between the top edge of @c contentView and its superview. */
@property(nonatomic, strong, nonnull) NSLayoutConstraint *contentViewTopConstraint;

/** The constraint between the bottom edge of @c contentView and its superview. */
@property(nonatomic, strong, nonnull) NSLayoutConstraint *contentViewBottomConstraint;

/** The constraint between the trailing edge of @c contentView and its superview. */
@property(nonatomic, strong, nonnull) NSLayoutConstraint *contentViewTrailingConstraint;

/** The constraint for the leading edge of @c contentView in a horizontal layout. */
@property(nonatomic, strong, nonnull)
    NSLayoutConstraint *contentViewHorizontalLayoutLeadingConstraint;

/** The constraint for the leading edge of @c contentView in a vertical layout. */
@property(nonatomic, strong, nonnull)
    NSLayoutConstraint *contentViewVerticalLayoutLeadingConstraint;

/** The haptics generator. */
@property(nonatomic, strong) UIImpactFeedbackGenerator *hapticsGenerator;

/**
 Configures whether the navigation bar should use vertical layout.

 Default @c NO.
 */
@property(nonatomic, assign) BOOL enableVerticalLayout;

@end

@implementation MDCBottomNavigationBarController

- (instancetype)init {
  self = [super init];
  if (self) {
    _hapticsGenerator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    _enableHaptics = NO;
    _navigationBar = [[MDCBottomNavigationBar alloc] init];
    _content = [[UIView alloc] init];
    _selectedIndex = NSNotFound;
    _dismissingLargeItemView = NO;
    _navigationBarVerticalLayoutConstraints = [NSMutableArray array];
    _navigationBarHorizontalLayoutConstraints = [NSMutableArray array];
    _contentInsets = UIEdgeInsetsZero;
    _contentCornerRadius = 0;

    _longPressPopUpViewEnabled = NO;

    [_navigationBar addObserver:self
                     forKeyPath:NSStringFromSelector(@selector(items))
                        options:NSKeyValueObservingOptionNew
                        context:kObservationContext];
    _enableVerticalLayout = NO;
    // TODO(b/276340214): Change this to automatic once bug is resolved.
    _layoutMode = MDCBottomNavigationBarLayoutModeHorizontal;
    _displayItemTitlesInVerticalLayout = NO;
  }

  return self;
}

- (void)dealloc {
  [_navigationBar removeObserver:self forKeyPath:NSStringFromSelector(@selector(items))];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.navigationBar.delegate = self;

  // Add subviews and create their constraints
  [self.view addSubview:self.content];
  [self.view addSubview:self.navigationBar];
  [self loadConstraints];

  if (self.isLongPressPopUpViewEnabled && !self.isNavigationBarLongPressRecognizerRegistered) {
    [self.navigationBar addGestureRecognizer:self.navigationBarLongPressRecognizer];
  }

  // The start up check for should use vertical layout is different from the check used
  // while the view is transitioning to a new size.
  BOOL shouldUseVerticalLayout = [self shouldUseVerticalLayout];
  if (shouldUseVerticalLayout != self.enableVerticalLayout &&
      self.layoutMode == MDCBottomNavigationBarLayoutModeAutomatic) {
    self.enableVerticalLayout = shouldUseVerticalLayout;
  }
}

- (BOOL)shouldUseVerticalLayout {
  BOOL allSizeClassesRegular =
      self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular &&
      self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
  BOOL shouldUseVerticalLayout =
      self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact ||
      allSizeClassesRegular;

  return shouldUseVerticalLayout;
}

- (void)viewSafeAreaInsetsDidChange {
  [super viewSafeAreaInsetsDidChange];
  [self updateNavigationBarInsets];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];

  [self updateNavigationBarInsets];
}

- (void)hideNavigationBarHelper:(BOOL)hidden {
  MDCBottomNavigationBar *navigationBar = self.navigationBar;
  self.navigationBarItemsBottomAnchorConstraint.active =
      !hidden && !navigationBar.enableVerticalLayout;
  if (!navigationBar.enableVerticalLayout) {
    CGFloat height = CGRectGetHeight(navigationBar.frame);
    self.navigationBarBottomAnchorConstraint.constant = hidden ? height : 0;
    self.navigationBarLeadingAnchorConstraint.constant = 0;
  } else {
    CGFloat width = CGRectGetWidth(navigationBar.frame);
    self.navigationBarBottomAnchorConstraint.constant = 0;
    self.navigationBarLeadingAnchorConstraint.constant = hidden ? -width : 0;
  }
}

- (void)setLayoutMode:(MDCBottomNavigationBarLayoutMode)layoutMode {
  if (_layoutMode == layoutMode) {
    return;
  }
  _layoutMode = layoutMode;
  if (_layoutMode == MDCBottomNavigationBarLayoutModeVertical) {
    self.enableVerticalLayout = YES;
  } else if (_layoutMode == MDCBottomNavigationBarLayoutModeHorizontal) {
    self.enableVerticalLayout = NO;
  } else {
    BOOL shouldUseVerticalLayout = [self shouldUseVerticalLayout];
    if (self.enableVerticalLayout != shouldUseVerticalLayout) {
      self.enableVerticalLayout = shouldUseVerticalLayout;
    }
  }
}

- (BOOL)useVerticalLayoutAfterTransitioningToSize:(CGSize)size {
  BOOL allSizeClassesRegular =
      self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular &&
      self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
  // This is calculated with the future view size and current size classes to determine if
  // vertical layout should be used.
  BOOL shouldUseVerticalLayout =
      (size.width > size.height &&
       self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular) ||
      allSizeClassesRegular;
  return shouldUseVerticalLayout;
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  if (self.layoutMode != MDCBottomNavigationBarLayoutModeAutomatic) {
    [self.navigationBar invalidateIntrinsicContentSize];
    return;
  }
  BOOL enableVerticalLayout = [self useVerticalLayoutAfterTransitioningToSize:size];
  if (enableVerticalLayout == self.enableVerticalLayout) {
    return;
  }
  // The setter is not used here since the setter also sets the navigationBar's enableVerticalLayout
  // flag and we set that here manually to control animations.
  _enableVerticalLayout = enableVerticalLayout;
  [coordinator
      animateAlongsideTransition:^(
          id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        [UIView animateWithDuration:kNavigationBarHideShowAnimationDuration
            animations:^{
              [self hideNavigationBarHelper:YES];
              [self.view layoutIfNeeded];
              [self updateNavigationBarInsets];
            }
            completion:^(BOOL finished) {
              self.navigationBar.enableVerticalLayout = self.enableVerticalLayout;
              [self loadConstraintsBasedOnRule];
              [self hideNavigationBarHelper:YES];
              [self.view layoutIfNeeded];
              [self updateNavigationBarInsets];
            }];
      }
      completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
        [self.navigationBar invalidateIntrinsicContentSize];
        [self hideNavigationBarHelper:NO];
        void (^lastAnimations)(void) = ^{
          [self.view layoutIfNeeded];
          [self updateNavigationBarInsets];
        };

        [UIView animateWithDuration:kNavigationBarHideShowAnimationDuration
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:lastAnimations
                         completion:nil];

        if ([self.delegate
                respondsToSelector:@selector(bottomNavigationBarControllerDidUpdateLayout)]) {
          [self.delegate bottomNavigationBarControllerDidUpdateLayout];
        }
      }];
}

- (void)setSelectedViewController:(nullable UIViewController *)selectedViewController {
  // Assert that the given VC is one of our view controllers or it is nil (we are unselecting)
  NSAssert(
      selectedViewController == nil || [self.viewControllers containsObject:selectedViewController],
      @"Attempting to set BottomBarViewControllers to a view controller it does not contain");

  // Early return if we are already set to the given VC
  if (self.selectedViewController == selectedViewController) {
    return;
  }

  // Remove current VC and add new one.
  [self.selectedViewController.view removeFromSuperview];
  [self.content addSubview:selectedViewController.view];
  [self addConstraintsForChildViewControllerView:selectedViewController.view];
  UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);

  // Set the iVar and update selected index
  _selectedViewController = selectedViewController;
  self.selectedIndex = [self.viewControllers indexOfObject:selectedViewController];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
  // If we are setting to NSNotFound deselect the items
  if (selectedIndex == NSNotFound) {
    [self deselectCurrentItem];
    return;
  }

  BOOL outOfBounds = selectedIndex >= self.viewControllers.count ||
                     selectedIndex >= self.navigationBar.items.count;

  NSAssert(!outOfBounds,
           @"Attempting to set BottomBarViewController's selectedIndex to %li. This"
            " value is not within the bounds of the navigation bar's items and/or view controllers",
           (unsigned long)selectedIndex);

  // Early return if we are out of bounds or if the index is already selected.
  if (outOfBounds || selectedIndex == _selectedIndex) {
    return;
  }

  // Update the selected index value and views.
  _selectedIndex = selectedIndex;
  [self updateViewsForSelectedIndex:selectedIndex];
}

- (void)addNewChildViewControllers:(NSArray<UIViewController *> *)newChildViewControllers {
  for (UIViewController *viewController in newChildViewControllers) {
    [self addChildViewController:viewController];
    [viewController didMoveToParentViewController:self];
  }
}

- (NSArray<UIViewController *> *)viewControllers {
  return [self.childViewControllers copy];
}

- (void)setEnableVerticalLayout:(BOOL)enableVerticalLayout {
  if (_enableVerticalLayout == enableVerticalLayout) {
    return;
  }
  _enableVerticalLayout = enableVerticalLayout;
  self.navigationBar.enableVerticalLayout = enableVerticalLayout;
  [self loadConstraintsBasedOnRule];
}

- (void)setDisplayItemTitlesInVerticalLayout:(BOOL)displayItemTitlesInVerticalLayout {
  if (_displayItemTitlesInVerticalLayout == displayItemTitlesInVerticalLayout) {
    return;
  }
  _displayItemTitlesInVerticalLayout = displayItemTitlesInVerticalLayout;
  self.navigationBar.displayItemTitlesInVerticalLayout = displayItemTitlesInVerticalLayout;
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers {
  [self deselectCurrentItem];
  [self removeExistingViewControllers];

  [self addNewChildViewControllers:[viewControllers copy]];
  self.navigationBar.items = [self tabBarItemsForViewControllers:self.childViewControllers];

  self.selectedViewController = self.childViewControllers.firstObject;
}

- (void)setLongPressPopUpViewEnabled:(BOOL)isLongPressPopUpViewEnabled {
  _longPressPopUpViewEnabled = isLongPressPopUpViewEnabled;

  if (isLongPressPopUpViewEnabled && !self.isNavigationBarLongPressRecognizerRegistered) {
    [self.navigationBar addGestureRecognizer:self.navigationBarLongPressRecognizer];
  } else if (!isLongPressPopUpViewEnabled && self.isNavigationBarLongPressRecognizerRegistered) {
    [self.navigationBar removeGestureRecognizer:self.navigationBarLongPressRecognizer];
  }
}

- (nullable UIViewController *)childViewControllerForStatusBarStyle {
  return self.selectedViewController;
}

- (nullable UIViewController *)childViewControllerForStatusBarHidden {
  return self.selectedViewController;
}

- (nullable UIViewController *)childViewControllerForHomeIndicatorAutoHidden {
  return self.selectedViewController;
}

- (nullable UIViewController *)childViewControllerForScreenEdgesDeferringSystemGestures {
  return self.selectedViewController;
}

- (UILongPressGestureRecognizer *)navigationBarLongPressRecognizer {
  if (!_navigationBarLongPressRecognizer) {
    _navigationBarLongPressRecognizer = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleNavigationBarLongPress:)];
    _navigationBarLongPressRecognizer.numberOfTouchesRequired = kLongPressNumberOfTouchesRequired;
    _navigationBarLongPressRecognizer.minimumPressDuration = kLongPressMinimumPressDuration;
  }

  return _navigationBarLongPressRecognizer;
}

#pragma mark - NavigationBar visibility

- (void)setNavigationBarHidden:(BOOL)navigationBarHidden {
  [self setNavigationBarHidden:navigationBarHidden animated:NO];
}

- (void)setNavigationBarHidden:(BOOL)hidden animated:(BOOL)animated {
  if (hidden == _navigationBarHidden) {
    return;
  }

  _navigationBarHidden = hidden;

  MDCBottomNavigationBar *navigationBar = self.navigationBar;
  [self hideNavigationBarHelper:hidden];

  void (^completionBlock)(BOOL) = ^(BOOL finished) {
    // Update the end hidden state of the navigation bar if it was not interrupted (the end state
    // matches the current state). Otherwise an already scheduled animation will take care of this.
    if (finished) {
      navigationBar.hidden = hidden;
    }
  };

  // Immediatelly update the navigation bar's hidden state when it is going to become visible to be
  // able to see the animation).
  if (!hidden) {
    navigationBar.hidden = hidden;
  }

  void (^animations)(void) = ^{
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self updateNavigationBarInsets];
  };

  NSTimeInterval duration = animated ? kNavigationBarHideShowAnimationDuration : 0;
  if (animated) {
    [UIView animateWithDuration:duration animations:animations completion:completionBlock];
  } else {
    animations();
    completionBlock(YES);
  }
}

#pragma mark - MDCBottomNavigationBarDelegate

- (void)bottomNavigationBar:(MDCBottomNavigationBar *)bottomNavigationBar
              didSelectItem:(UITabBarItem *)item {
  // Early return if we cannot find the view controller.
  NSUInteger index = [self.navigationBar.items indexOfObject:item];
  if (index >= [self.viewControllers count] || index == NSNotFound) {
    return;
  }

  // Update selected view controller
  UIViewController *selectedViewController = [self.viewControllers objectAtIndex:index];

  if (self.selectedViewController != selectedViewController) {
    self.selectedViewController = selectedViewController;
    // Play haptics pattern if haptics are supported and enabled.
    if (self.enableHaptics) {
      [self.hapticsGenerator impactOccurred];
    }
  }

  // Notify the delegate.
  if ([self.delegate respondsToSelector:@selector(bottomNavigationBarController:
                                                        didSelectViewController:)]) {
    [self.delegate bottomNavigationBarController:self
                         didSelectViewController:selectedViewController];
  }
}

- (BOOL)bottomNavigationBar:(MDCBottomNavigationBar *)bottomNavigationBar
           shouldSelectItem:(UITabBarItem *)item {
  NSUInteger index = [self.navigationBar.items indexOfObject:item];
  if (index >= [self.viewControllers count] || index == NSNotFound) {
    return NO;
  }

  // Pass the response to the delegate if they want to handle this request.
  if ([self.delegate respondsToSelector:@selector(bottomNavigationBarController:
                                                     shouldSelectViewController:)]) {
    UIViewController *viewControllerToSelect = [self.viewControllers objectAtIndex:index];
    return [self.delegate bottomNavigationBarController:self
                             shouldSelectViewController:viewControllerToSelect];
  }

  return YES;
}

#pragma mark - Key Value Observation Methods

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context {
  if (context != kObservationContext) {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
  }

  id newValue = [change objectForKey:NSKeyValueChangeNewKey];
  if (object == self.navigationBar &&
      [keyPath isEqualToString:NSStringFromSelector(@selector(items))] &&
      [newValue isKindOfClass:[NSArray class]]) {
    [self didUpdateNavigationBarItemsWithNewValue:(NSArray *)newValue];
  }
}

- (void)didUpdateNavigationBarItemsWithNewValue:(NSArray *)items {
  // Verify tab bar items correspond with the view controllers tab bar items.
  if (items.count != self.viewControllers.count) {
    [[self unauthorizedItemsChangedException] raise];
  }

  // Verify each new and the view controller's tab bar items are equal.
  for (NSUInteger i = 0; i < self.viewControllers.count; i++) {
    UITabBarItem *viewControllerTabBarItem = [self.viewControllers objectAtIndex:i].tabBarItem;
    UITabBarItem *newTabBarItem = [items objectAtIndex:i];
    if (![viewControllerTabBarItem isEqual:newTabBarItem]) {
      [[self unauthorizedItemsChangedException] raise];
    }
  }
}

#pragma mark - Touch Events

/** Handles long press gesture recognizer event updates. */
- (void)handleNavigationBarLongPress:(UIGestureRecognizer *)recognizer {
  CGPoint touchPoint = [recognizer locationInView:self.navigationBar];
  switch (recognizer.state) {
    case UIGestureRecognizerStateBegan:
    case UIGestureRecognizerStateChanged:
      [self handleNavigationBarLongPressUpdatedForPoint:touchPoint];
      break;
    default:
      [self handleNavigationBarLongPressEndedForPoint:touchPoint];
      break;
  }
}

/**
 Handles when the navigation bar long press gesture recognizer gesture has been initiated or the
 touch point was updated.
 @param point CGPoint The point within @c navigationBar coordinate space.
 */
- (void)handleNavigationBarLongPressUpdatedForPoint:(CGPoint)point {
  if (!self.isContentSizeCategoryAccessibilityCategory) {
    return;
  }

  UITabBarItem *item = [self.navigationBar tabBarItemForPoint:point];
  if (!item && CGRectContainsPoint(self.navigationBar.bounds, point)) {
    // The item may be nil when the touch is still within the frame of the navigation bar, but not
    // within the frame of an item view. In this case the large item view should still display the
    // last long pressed item.
    return;
  } else if (!item) {
    [self handleNavigationBarLongPressEndedForPoint:point];
    return;
  }

  if (!self.largeItemDialog) {
    self.largeItemDialog = [[MDCBottomNavigationLargeItemDialogView alloc] init];
  }
  [self.largeItemDialog updateWithTabBarItem:item];
  [self showLargeItemDialog];
}

/**
 Handles when the navigation bar long press gesture recognizer gesture has concluded.
 @param point CGPoint The point within @c navigationBar coordinate space.
 */
- (void)handleNavigationBarLongPressEndedForPoint:(CGPoint)point {
  UITabBarItem *item = [self.navigationBar tabBarItemForPoint:point];
  NSUInteger index = [self.navigationBar.items indexOfObject:item];
  if (index != NSNotFound && index < self.viewControllers.count) {
    self.selectedIndex = index;
  }
  [self dismissLargeItemDialog];
}

#pragma mark - State Restoration Methods

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
  for (UIViewController *childViewController in self.childViewControllers) {
    if (childViewController.restorationIdentifier.length > 0) {
      [coder encodeObject:childViewController];
    }
  }

  if (self.selectedViewController) {
    [coder encodeObject:self.selectedViewController forKey:kSelectedViewControllerRestorationKey];
  }

  [super encodeRestorableStateWithCoder:coder];
}

- (void)decodeRestorableStateWithCoder:(NSCoder *)coder {
  UIViewController *selectedViewController =
      DecodeViewController(coder, kSelectedViewControllerRestorationKey);
  if (selectedViewController && [self.viewControllers containsObject:selectedViewController]) {
    self.selectedViewController = selectedViewController;
  }

  [super decodeRestorableStateWithCoder:coder];
}

#pragma mark - Private Methods

- (void)removeExistingViewControllers {
  NSArray<UIViewController *> *childViewControllers = self.childViewControllers;
  for (UIViewController *childViewController in childViewControllers) {
    [childViewController willMoveToParentViewController:nil];
    [childViewController.view removeFromSuperview];
    [childViewController removeFromParentViewController];
  }
}

/**
 Adjusts all relevant insets in subviews and the selected child view controller. This include @c
 safeAreaInsets and scroll view insets.  This will ensure that although the child view controller's
 view is positioned behind the bar, it can still lay out its content above the Bottom Navigation
 bar.  For a UIScrollView, this means manipulating both @c contentInset and
 @c scrollIndicatorInsets.
 */
- (void)updateNavigationBarInsets {
  UIEdgeInsets currentSafeAreaInsets = self.view.safeAreaInsets;

  CGFloat navigationBarHeight =
      self.isNavigationBarHidden ? 0 : CGRectGetHeight(self.navigationBar.frame);

  CGFloat bottomInsetAdjustment =
      self.enableVerticalLayout ? 0 : navigationBarHeight - currentSafeAreaInsets.bottom;
  self.selectedViewController.additionalSafeAreaInsets =
      UIEdgeInsetsMake(0, 0, bottomInsetAdjustment, 0);
}

/**
 Deselects the currently set item.  Sets the selectedIndex to NSNotFound, the naviagation bar's
 selected item to nil, and the selectedViewController to nil.
 */
- (void)deselectCurrentItem {
  _selectedIndex = NSNotFound;
  self.navigationBar.selectedItem = nil;

  // Force removal of the currently selected viewcontroller if there is one.
  self.selectedViewController = nil;
}

/**
 Sets the selected view controller to the corresponding index and updates the navigation bar's
 selected item.
 */
- (void)updateViewsForSelectedIndex:(NSUInteger)index {
  // Update the selected view controller
  UIViewController *selectedViewController = [self.viewControllers objectAtIndex:index];
  self.selectedViewController = selectedViewController;

  // Update the navigation bar's selected item.
  self.navigationBar.selectedItem = selectedViewController.tabBarItem;
  [self setNeedsStatusBarAppearanceUpdate];
  [self setNeedsUpdateOfHomeIndicatorAutoHidden];
  [self setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
}

/**
 Hooks up the constraints for the subviews of this controller.  Namely the content view and the
 navigation bar.
 */
- (void)loadConstraints {
  [self loadConstraintsForNavigationBar];
  [self loadConstraintsForContentContainerView];
  [self loadConstraintsBasedOnRule];
}

- (void)loadConstraintsBasedOnRule {
  if (self.enableVerticalLayout) {
    [NSLayoutConstraint deactivateConstraints:self.navigationBarHorizontalLayoutConstraints];
    [NSLayoutConstraint activateConstraints:self.navigationBarVerticalLayoutConstraints];
  } else {
    [NSLayoutConstraint deactivateConstraints:self.navigationBarVerticalLayoutConstraints];
    [NSLayoutConstraint activateConstraints:self.navigationBarHorizontalLayoutConstraints];
  }
}

- (void)loadConstraintsForNavigationBar {
  self.navigationBar.translatesAutoresizingMaskIntoConstraints = NO;
  self.navigationBarLeadingAnchorConstraint = [self.navigationBar.leadingAnchor
      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor];
  self.navigationBarLeadingAnchorConstraint.active = YES;
  self.navigationBarBottomAnchorConstraint =
      [self.navigationBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
  self.navigationBarBottomAnchorConstraint.active = YES;
  self.navigationBarItemsBottomAnchorConstraint = [self.navigationBar.barItemsBottomAnchor
      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];

  [self.navigationBarVerticalLayoutConstraints
      addObject:[self.navigationBar.topAnchor constraintEqualToAnchor:self.view.topAnchor]];

  [self.navigationBarHorizontalLayoutConstraints
      addObject:[self.view.safeAreaLayoutGuide.trailingAnchor
                    constraintEqualToAnchor:self.navigationBar.trailingAnchor]];
  [self.navigationBarHorizontalLayoutConstraints
      addObject:self.navigationBarItemsBottomAnchorConstraint];
}

- (void)setBackgroundColor:(nullable UIColor *)color {
  if (_backgroundColor != color) {
    _backgroundColor = color;
    self.view.backgroundColor = color;
    self.navigationBar.backgroundColor = color;
  }
}

- (void)setContentInsets:(UIEdgeInsets)contentInsets {
  if (UIEdgeInsetsEqualToEdgeInsets(_contentInsets, contentInsets)) {
    return;
  }

  _contentInsets = contentInsets;

  self.contentViewTopConstraint.constant = self.contentInsets.top;
  self.contentViewBottomConstraint.constant = self.contentInsets.bottom;
  self.contentViewTrailingConstraint.constant = self.contentInsets.right;

  self.contentViewVerticalLayoutLeadingConstraint.constant = self.contentInsets.left;
  self.contentViewHorizontalLayoutLeadingConstraint.constant = self.contentInsets.left;
}

- (void)setContentCornerRadius:(CGFloat)contentCornerRadius {
  if (contentCornerRadius == _contentCornerRadius) {
    return;
  }

  _contentCornerRadius = contentCornerRadius;
  self.content.layer.cornerRadius = self.contentCornerRadius;
  self.content.layer.masksToBounds = self.contentCornerRadius != 0 ? YES : NO;
}

- (void)loadConstraintsForContentContainerView {
  self.content.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentViewTopConstraint =
      [self.content.topAnchor constraintEqualToAnchor:self.view.topAnchor
                                             constant:self.contentInsets.top];
  self.contentViewBottomConstraint =
      [self.content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
                                                constant:self.contentInsets.bottom];
  self.contentViewTrailingConstraint =
      [self.content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                  constant:self.contentInsets.right];
  [NSLayoutConstraint activateConstraints:@[
    self.contentViewTopConstraint,
    self.contentViewBottomConstraint,
    self.contentViewTrailingConstraint,
  ]];

  // Rule-based constraits.
  self.contentViewVerticalLayoutLeadingConstraint =
      [self.content.leadingAnchor constraintEqualToAnchor:self.navigationBar.trailingAnchor
                                                 constant:self.contentInsets.left];
  self.contentViewHorizontalLayoutLeadingConstraint =
      [self.content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                 constant:self.contentInsets.left];

  [self.navigationBarVerticalLayoutConstraints
      addObject:self.contentViewVerticalLayoutLeadingConstraint];
  [self.navigationBarHorizontalLayoutConstraints
      addObject:self.contentViewHorizontalLayoutLeadingConstraint];
}

/**
 Pins the given view to the edges of the content view.
 */
- (void)addConstraintsForChildViewControllerView:(UIView *)view {
  view.translatesAutoresizingMaskIntoConstraints = NO;
  [view.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor].active = YES;
  [view.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor].active = YES;
  [view.topAnchor constraintEqualToAnchor:self.content.topAnchor].active = YES;
  [view.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor].active = YES;
}

/** Maps an array of view controllers to their corrisponding tab bar items. */
- (NSArray<UITabBarItem *> *)tabBarItemsForViewControllers:
    (NSArray<UIViewController *> *)viewControllers {
  NSMutableArray<UITabBarItem *> *tabBarItems = [NSMutableArray array];
  for (UIViewController *viewController in viewControllers) {
    UITabBarItem *tabBarItem = viewController.tabBarItem;
    NSAssert(tabBarItem != nil,
             @"%@'s tabBarItem is nil. Please ensure that each view controller "
              "added to %@ has set its tab bar item property",
             viewController, NSStringFromClass([self class]));

    if (tabBarItem) {
      [tabBarItems addObject:tabBarItem];
    }
  }

  return tabBarItems;
}

/**
 Returns an exception for when the navigation bar's items are changed from outside of this class.
 */
- (NSException *)unauthorizedItemsChangedException {
  NSString *reason = [NSString
      stringWithFormat:
          @"Attempting to set %@'s navigation bar items.  Please instead use setViewControllers:",
          NSStringFromClass([self class])];
  return [NSException exceptionWithName:NSInternalInconsistencyException
                                 reason:reason
                               userInfo:nil];
}

/** Adds the large item dialog to the view hierarchy and animates its presentation. */
- (void)showLargeItemDialog {
  if (self.largeItemDialog.superview) {
    return;
  }

  self.largeItemDialog.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.largeItemDialog];

  UIWindow *window = self.largeItemDialog.window;
  [self.largeItemDialog.heightAnchor constraintEqualToConstant:kLargeItemViewHeight].active = YES;
  [self.largeItemDialog.widthAnchor constraintEqualToConstant:kLargeItemViewWidth].active = YES;
  [self.largeItemDialog.centerXAnchor constraintEqualToAnchor:window.centerXAnchor].active = YES;
  [self.largeItemDialog.centerYAnchor constraintEqualToAnchor:window.centerYAnchor].active = YES;

  self.largeItemDialog.layer.opacity = 0;
  self.largeItemDialog.transform = LargeItemViewAnimationTransitionTransform();
  [UIView animateWithDuration:kLargeItemViewAnimationDuration
                   animations:^{
                     self.largeItemDialog.layer.opacity = 1;
                     self.largeItemDialog.transform = CGAffineTransformIdentity;
                   }];
}

/** Removes the large item dialog from the view hierarchy and animates its dismissal. */
- (void)dismissLargeItemDialog {
  if (!self.largeItemDialog.superview || self.isDismissingLargeItemDialog) {
    return;
  }

  self.dismissingLargeItemView = YES;
  [UIView animateWithDuration:kLargeItemViewAnimationDuration
      animations:^{
        self.largeItemDialog.layer.opacity = 0;
        self.largeItemDialog.transform = LargeItemViewAnimationTransitionTransform();
      }
      completion:^(BOOL finished) {
        if (finished) {
          [self.largeItemDialog removeFromSuperview];
        }
        self.dismissingLargeItemView = NO;
      }];
}

- (BOOL)isNavigationBarLongPressRecognizerRegistered {
  return
      [self.navigationBar.gestureRecognizers containsObject:self.navigationBarLongPressRecognizer];
}

/** Returns if the receiver's size category is an accessibility category. */
- (BOOL)isContentSizeCategoryAccessibilityCategory {
  UIContentSizeCategory sizeCategory = UIContentSizeCategoryLarge;
  sizeCategory = self.traitCollection.preferredContentSizeCategory;
  return UIContentSizeCategoryIsAccessibilityCategory(sizeCategory);
}

@end

NS_ASSUME_NONNULL_END
