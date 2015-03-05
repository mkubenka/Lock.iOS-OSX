// A0GooglePlusAuthenticator.m
//
// Copyright (c) 2015 Auth0 (http://auth0.com)
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

#import "A0GooglePlusAuthenticator.h"
#import "A0Strategy.h"
#import <googleplus-ios-sdk/GooglePlus.h>
#import <googleplus-ios-sdk/GoogleOpenSource.h>
#import "A0APIClient.h"
#import "A0IdentityProviderCredentials.h"
#import "A0Errors.h"

@interface A0GooglePlusAuthenticator () <GPPSignInDelegate>
@property (copy, nonatomic) void (^successBlock)(A0UserProfile *, A0Token *);
@property (copy, nonatomic) void (^failureBlock)(NSError *);
@property (strong, nonatomic) A0AuthParameters *parameters;
@end

@implementation A0GooglePlusAuthenticator

AUTH0_DYNAMIC_LOGGER_METHODS

- (instancetype)initWithClientId:(NSString *)clientId {
    return [self initWithClientId:clientId scopes:nil];
}

- (instancetype)initWithClientId:(NSString *)clientId scopes:(NSArray *)scopes {
    self = [super init];
    if (self) {
        GPPSignIn *signIn = [GPPSignIn sharedInstance];
        signIn.clientID = clientId;
        NSMutableSet *scopeSet = [[NSMutableSet alloc] init];
        [scopeSet addObject:kGTLAuthScopePlusLogin];
        [scopeSet addObject:kGTLAuthScopePlusUserinfoEmail];
        if (scopes) {
            [scopeSet addObjectsFromArray:scopes];
        }
        signIn.scopes = [scopeSet allObjects];
        signIn.delegate = self;
        A0LogDebug(@"Initialised Google+ authenticator with scopes %@", signIn.scopes);
        [self clearCallbacks];
    }
    return self;
}

+ (instancetype)newAuthenticatorWithClientId:(NSString *)clientId {
    return [[A0GooglePlusAuthenticator alloc] initWithClientId:clientId];
}

+ (instancetype)newAuthenticatorWithClientId:(NSString *)clientId andScopes:(NSArray *)scopes {
    return [[A0GooglePlusAuthenticator alloc] initWithClientId:clientId scopes:scopes];
}

- (NSString *)identifier {
    return A0StrategyNameGooglePlus;
}

- (void)authenticateWithParameters:(A0AuthParameters *)parameters
                           success:(void (^)(A0UserProfile *, A0Token *))success
                           failure:(void (^)(NSError *))failure {
    NSAssert(success != nil, @"Must provide a non-nil success block");
    NSAssert(failure != nil, @"Must provide a non-nil failure block");
    self.successBlock = success;
    self.failureBlock = failure;
    self.parameters = parameters;
    GPPSignIn *signIn = [GPPSignIn sharedInstance];
    [signIn authenticate];
    A0LogVerbose(@"Starting Google+ Authentication...");
}

- (void)clearSessions {
    self.parameters = nil;
    [self clearCallbacks];
    [[GPPSignIn sharedInstance] signOut];
    A0LogVerbose(@"Cleared Google+ session");
}

- (BOOL)handleURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication {
    return [GPPURLHandler handleURL:url sourceApplication:sourceApplication annotation:nil];
}

#pragma mark - GPPSignInDelegate

- (void)finishedWithAuth:(GTMOAuth2Authentication *)auth error:(NSError *)error {
    if (error) {
        A0LogError(@"Failed to authenticate with Google+ with error %@", error);
        self.failureBlock([A0Errors googleplusFailed]);
    } else {
        A0LogVerbose(@"Authenticated with Google+");
        A0IdentityProviderCredentials *credentials = [[A0IdentityProviderCredentials alloc] initWithAccessToken:auth.accessToken];
        [[A0APIClient sharedClient] authenticateWithSocialConnectionName:A0StrategyNameGooglePlus
                                                             credentials:credentials
                                                              parameters:self.parameters
                                                                 success:self.successBlock
                                                                 failure:self.failureBlock];
        [self clearCallbacks];
        self.parameters = nil;
    }
}

#pragma mark - Utility methods

- (void)clearCallbacks {
    self.failureBlock = ^(NSError *error) {};
    self.successBlock = ^(A0UserProfile* profile, A0Token *token) {};
}
@end
