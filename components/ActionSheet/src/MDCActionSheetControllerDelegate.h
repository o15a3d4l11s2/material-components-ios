// Copyright 2020-present the Material Components for iOS authors. All Rights Reserved.
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


#import <UIKit/UIKit.h>

@class MDCActionSheetController;

API_DEPRECATED_BEGIN("🕘 Schedule time to migrate. "
                     "Follow go/material-ios-menus to use UIMenu instead."
                     "Use UIAlertController in action sheet style for destructive confirmations. "
                     "This is go/material-ios-migrations#not-scriptable 🕘",
                     ios(12, 12))

/**
 Defines methods that allows the adopting delegate to respond to messages from an
 @c MDCActionSheetController.
 */
API_DEPRECATED("🕘 Schedule time to migrate. "
               "Follow go/material-ios-menus to use UIMenu instead."
               "Use UIAlertController in action sheet style for destructive "
               "confirmations. "
               "This is go/material-ios-migrations#not-scriptable 🕘",
               ios(12, 12))
@protocol MDCActionSheetControllerDelegate <NSObject>
@optional

/**
 Tells the delegate that the action sheet was dismissed.

 @param actionSheetController the @c MDCActionSheetController that was dismissed.
 */
- (void)actionSheetControllerDidDismiss:(nonnull MDCActionSheetController *)actionSheetController;

/**
 Tells the delegate that the action sheet has completed animating offscreen.

 @param actionSheetController the @c MDCActionSheetController that was dismissed.
 */
- (void)actionSheetControllerDismissalAnimationCompleted:
    (nonnull MDCActionSheetController *)actionSheetController;

/**
 Tells the delegate that the action sheet will display a view.
 */
- (void)actionSheetController:(nonnull MDCActionSheetController *)actionSheetController
              willDisplayView:(nonnull UIView *)view
            forRowAtIndexPath:(nonnull NSIndexPath *)indexPath;
@end

API_DEPRECATED_END
