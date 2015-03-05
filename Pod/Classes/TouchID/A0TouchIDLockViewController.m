//  A0TouchIDAuthenticationViewController.m
//
// Copyright (c) 2014 Auth0 (http://auth0.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "A0TouchIDLockViewController.h"

#import <SimpleKeychain/A0SimpleKeychain+KeyPair.h>
#import <TouchIDAuth/A0TouchIDAuthentication.h>
#import <libextobjc/EXTScope.h>
#import <SimpleKeychain/A0SimpleKeychain.h>
#import "A0TouchIDRegisterViewController.h"
#import "A0APIClient.h"
#import "A0AuthParameters.h"
#import "A0UserProfile.h"
#import "A0Token.h"
#import "A0UserAPIClient.h"
#import "A0Theme.h"

NSString * const A0ThemeTouchIDLockButtonImageNormalName = @"A0ThemeTouchIDLockButtonImageNormalName";
NSString * const A0ThemeTouchIDLockButtonImageHighlightedName = @"A0ThemeTouchIDLockButtonImageHighlightedName";
NSString * const A0ThemeTouchIDLockContainerBackgroundColor = @"A0ThemeTouchIDLockContainerBackgroundColor";

@interface A0TouchIDLockViewController ()

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UIImageView *iconImageView;
@property (weak, nonatomic) IBOutlet UIView *iconContainerView;
@property (weak, nonatomic) IBOutlet UIView *loadingView;
@property (weak, nonatomic) IBOutlet UIView *touchIDView;
@property (weak, nonatomic) IBOutlet UIButton *closeButton;
@property (weak, nonatomic) IBOutlet UIButton *touchIDButton;
@property (weak, nonatomic) IBOutlet UILabel *messageLabel;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;

@property (strong, nonatomic) A0TouchIDAuthentication *authentication;
@property (strong, nonatomic) A0UserAPIClient *userClient;

- (IBAction)checkTouchID:(id)sender;

@end

@implementation A0TouchIDLockViewController

AUTH0_DYNAMIC_LOGGER_METHODS

- (instancetype)init {
    return [self initWithNibName:NSStringFromClass(self.class) bundle:[NSBundle bundleForClass:self.class]];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            self.modalPresentationStyle = UIModalPresentationFormSheet;
        }
        _authenticationParameters = [A0AuthParameters newDefaultParams];
        [_authenticationParameters setValue:@"Username-Password-Authentication" forKey:@"connection"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    @weakify(self);

    NSAssert(self.navigationController != nil, @"Must be inside a UINavigationController");
    self.navigationController.navigationBarHidden = YES;
    A0Theme *theme = [A0Theme sharedInstance];
    UIImage *image = [theme imageForKey:A0ThemeScreenBackgroundImageName];
    if (image) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        [self.view insertSubview:imageView atIndex:0];
    }
    self.view.backgroundColor = [theme colorForKey:A0ThemeScreenBackgroundColor];
    self.iconContainerView.backgroundColor = [theme colorForKey:A0ThemeIconBackgroundColor];
    self.iconImageView.image = [theme imageForKey:A0ThemeIconImageName];
    self.closeButton.enabled = self.closable;
    self.closeButton.hidden = !self.closable;
    self.closeButton.tintColor = [theme colorForKey:A0ThemeSecondaryButtonTextColor];
    UIImage *normalImage = [theme imageForKey:A0ThemeTouchIDLockButtonImageNormalName defaultImage:[self.touchIDButton imageForState:UIControlStateNormal]];
    [self.touchIDButton setImage:normalImage forState:UIControlStateNormal];
    UIImage *highlightedImage = [theme imageForKey:A0ThemeTouchIDLockButtonImageHighlightedName defaultImage:[self.touchIDButton imageForState:UIControlStateHighlighted]];
    [self.touchIDButton setImage:highlightedImage forState:UIControlStateHighlighted];
    self.touchIDView.backgroundColor = [theme colorForKey:A0ThemeTouchIDLockContainerBackgroundColor defaultColor:self.touchIDView.backgroundColor];
    self.messageLabel.font = [theme fontForKey:A0ThemeDescriptionFont];
    self.messageLabel.textColor = [theme colorForKey:A0ThemeDescriptionTextColor];
    self.activityIndicator.color = [theme colorForKey:A0ThemeTitleTextColor];
    self.titleLabel.text = A0LocalizedString(@"Login with TouchID");
    self.titleLabel.font = [theme fontForKey:A0ThemeTitleFont];
    self.titleLabel.textColor = [theme colorForKey:A0ThemeTitleTextColor];

    self.authentication = [[A0TouchIDAuthentication alloc] init];
    self.authentication.onError = ^(NSError *error) {
        @strongify(self);
        A0LogError(@"Failed to perform TouchID authentication with error %@", error);
        NSString *message;
        switch (error.code) {
            case A0TouchIDAuthenticationErrorTouchIDFailed:
            case A0TouchIDAuthenticationErrorTouchIDNotAvailable:
                message = error.localizedDescription;
                break;
            default:
                message = A0LocalizedString(@"Couldn't authenticate with TouchID. Please try again later!.");
                break;
        }
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:A0LocalizedString(@"There was an error logging in")
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:A0LocalizedString(@"OK")
                                              otherButtonTitles:nil];
        [alert show];
        self.touchIDView.hidden = NO;
        self.loadingView.hidden = YES;
    };

    NSString *userId = [[A0SimpleKeychain keychainWithService:@"TouchID"] stringForKey:@"auth0-userid"];
    if (!userId) {
        [self.authentication reset];
        A0LogDebug(@"Cleaning up key pairs of unknown user");
    }

    A0SimpleKeychain *keychain = [A0SimpleKeychain keychainWithService:@"TouchID"];
    self.authentication.registerPublicKey = ^(NSData *pubKey, A0RegisterCompletionBlock completionBlock, A0ErrorBlock errorBlock) {
        @strongify(self);
        A0TouchIDRegisterViewController *controller = [[A0TouchIDRegisterViewController alloc] init];
        controller.onCancelBlock = ^ {
            @strongify(self);
            [self.authentication reset];
            [self.navigationController popViewControllerAnimated:YES];
            self.touchIDView.hidden = NO;
            self.loadingView.hidden = YES;
        };
        controller.onRegisterBlock = ^(A0UserProfile *profile, A0Token *token) {
            @strongify(self);
            [self.navigationController popViewControllerAnimated:YES];
            A0LogDebug(@"User %@ registered. Uploading public key...", profile.userId);
            [keychain setString:profile.userId forKey:@"auth0-userid"];
            NSString *deviceName = [self deviceName];
            self.userClient = [A0UserAPIClient clientWithIdToken:token.idToken];
            [self.userClient removePublicKeyOfDevice:deviceName user:profile.userId success:^{
                @strongify(self);
                [self.userClient registerPublicKey:pubKey device:deviceName user:profile.userId success:completionBlock failure:errorBlock];
            } failure:^(NSError *error) {
                @strongify(self);
                A0LogWarn(@"Failed to remove public key. Please check that the user has only one Public key registered.");
                [self.userClient registerPublicKey:pubKey device:deviceName user:profile.userId success:completionBlock failure:errorBlock];
            }];
        };
        controller.authenticationParameters = self.authenticationParameters;
        [self.navigationController pushViewController:controller animated:YES];
    };
    self.authentication.jwtPayload = ^{
        NSString *userId = [keychain stringForKey:@"auth0-userid"];
        return @{
                 @"iss": userId,
                 };
    };

    self.authentication.authenticate = ^(NSString *jwt, A0ErrorBlock errorBlock) {
        @strongify(self);
        A0LogVerbose(@"Authenticating with signed JWT %@", jwt);
        A0APIClient *client = [A0APIClient sharedClient];
        [client loginWithIdToken:jwt
                      deviceName:[self deviceName]
                      parameters:self.authenticationParameters
                         success:self.onAuthenticationBlock
                         failure:errorBlock];
    };
}

- (void)close:(id)sender {
    A0LogVerbose(@"Dismissing TouchID view controller on user's request.");
    if (self.onUserDismissBlock) {
        self.onUserDismissBlock();
    }
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (void)checkTouchID:(id)sender {
    self.touchIDView.hidden = YES;
    self.loadingView.hidden = NO;
    [self.authentication start];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [[A0Theme sharedInstance] statusBarStyle];
}

#pragma mark - Utility methods

- (NSString *)deviceName {
    NSString *deviceName = [[UIDevice currentDevice] name];
    NSCharacterSet *setToFilter = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    deviceName = [[deviceName componentsSeparatedByCharactersInSet:setToFilter] componentsJoinedByString:@""];
    return deviceName;
}

@end
