//
//  RWSearchFormViewController.m
//  TwitterInstant
//
//  Created by Colin Eberhardt on 02/12/2013.
//  Copyright (c) 2013 Colin Eberhardt. All rights reserved.
//

#import "RWSearchFormViewController.h"
#import "RWSearchResultsViewController.h"

#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoa/RACEXTScope.h>

#import <Accounts/Accounts.h>
#import <Social/Social.h>

#import "RWTweet.h"
#import <NSArray+LinqExtensions.h>

typedef NS_ENUM(NSInteger, RWTwitterInstantError)
{
    RWTwitterInstantErrorAccessDenied,
    RWTwitterInstantErrorNoTwitterAccounts,
    RWTwitterInstantErrorInvalidResponse
};

static NSString *const RWTwitterInstantDomain = @"TwitterInstant";

@interface RWSearchFormViewController ()

@property (weak, nonatomic) IBOutlet UITextField *searchText;

@property (strong, nonatomic) RWSearchResultsViewController *resultsViewController;

@property (strong, nonatomic) ACAccountStore *accountStore;
@property (strong, nonatomic) ACAccountType *twitterAccountType;

@end

@implementation RWSearchFormViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.title = @"Twitter Instant";
  
  [self styleTextField:self.searchText];
  
  self.resultsViewController = self.splitViewController.viewControllers[1];
  
    //in order to avoid retain cycle in an elegant way
    RAC(self.searchText, backgroundColor) = [self.searchText.rac_textSignal map:^id(NSString *text) {
        return [self isValidSearchText:text]? [UIColor whiteColor]: [UIColor yellowColor];
    }];
    
    self.accountStore = [[ACAccountStore alloc] init];
    self.twitterAccountType = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    @weakify(self)
    [[[[[[[self requestAccessToTwitterSignal] then:^RACSignal *{ //drops 'next'; receives 'error'
        @strongify(self)
        return self.searchText.rac_textSignal;
    }]
    filter:^BOOL(NSString *text) {
        @strongify(self)
        return [self isValidSearchText:text];
    }]
    throttle:0.5]
    flattenMap:^RACStream *(NSString *text) {
        @strongify(self)
        return [self signalForSearchWithText:text];
    }]
    deliverOn:[RACScheduler mainThreadScheduler]]
    subscribeNext:^(NSDictionary *jsonSearchResult) {
        NSArray *statuses = jsonSearchResult[@"statuses"];
        NSArray *tweets = [statuses linq_select:^id(id tweet) {
            return [RWTweet tweetWithStatus:tweet];
        }];
        [self.resultsViewController displayTweets:tweets];
    } error:^(NSError *error) {
        NSLog(@"An error occurred: %@", error);
    }];
    
    
    
}

-(SLRequest *)requestForTwitterSearchWithText:(NSString *)text
{
    NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/1.1/search/tweets.json"];
    NSDictionary *params = @{@"q": text};
    SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeTwitter requestMethod:SLRequestMethodGET URL:url parameters:params];
    return request;
}

-(RACSignal *)signalForSearchWithText:(NSString *)text
{
    // 1 - define the error
    NSError *noAccountsError = [NSError errorWithDomain:RWTwitterInstantDomain code:RWTwitterInstantErrorNoTwitterAccounts userInfo:nil];
    NSError *invalidResponseError = [NSError errorWithDomain:RWTwitterInstantDomain code:RWTwitterInstantErrorInvalidResponse userInfo:nil];
    
    // 2 - create the signal block
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber)
    {
        @strongify(self)
        
        // 3 - create the request
        SLRequest *request = [self requestForTwitterSearchWithText:text];
        
        // 4 - supply a twitter account
        NSArray *twitterAccounts = [self.accountStore accountsWithAccountType:self.twitterAccountType];
        if (twitterAccounts.count == 0)
        {
            [subscriber sendError:noAccountsError];
        }
        else
        {
            [request setAccount:twitterAccounts.lastObject];
        }
        
        // 5 - perform the request
        [request performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error)
        {
            if (urlResponse.statusCode == 200)
            {
                // 6 - on success, parse the response
                NSDictionary *timelineData = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingAllowFragments error:nil];
                [subscriber sendNext:timelineData];
                [subscriber sendCompleted];
            }
            else
            {
                // 7 - send an error on failure
                [subscriber sendError:invalidResponseError];
            }
        }];
        return nil;
    }];
}

-(RACSignal *)requestAccessToTwitterSignal
{
    // 1 - define an error
    NSError *accessError = [NSError errorWithDomain:RWTwitterInstantDomain code:RWTwitterInstantErrorAccessDenied userInfo:nil];
    
    // 2 - create the signal
    @weakify(self)
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber)
    {
        // 3 - request access to twitter
        @strongify(self)
        [self.accountStore requestAccessToAccountsWithType:self.twitterAccountType options:nil completion:^(BOOL granted, NSError *error)
        {
            if (!granted)
            {
                [subscriber sendError:accessError];
            }
            else
            {
                [subscriber sendNext:nil];
                [subscriber sendCompleted];
            }
        }];
        return nil;
    }];
}

- (void)styleTextField:(UITextField *)textField {
  CALayer *textFieldLayer = textField.layer;
  textFieldLayer.borderColor = [UIColor grayColor].CGColor;
  textFieldLayer.borderWidth = 2.0f;
  textFieldLayer.cornerRadius = 0.0f;
}

- (BOOL)isValidSearchText:(NSString *)text
{
    return text.length > 2;
}

@end
