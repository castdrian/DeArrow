#import "BrandingClient.h"

#import <UIKit/UIKit.h>

@interface                                              BrandingCacheEntry : NSObject
@property (nonatomic, strong, nullable) BrandingRecord *record;
@property (nonatomic, strong) NSDate                   *expiresAt;
@end

@implementation BrandingCacheEntry
@end

@interface                                       ThumbnailCacheEntry : NSObject
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, strong) NSDate            *expiresAt;
@property (nonatomic) BOOL                       negative;
@end

@implementation ThumbnailCacheEntry
@end

@interface                                   BrandingRequestToken ()
@property (nonatomic, copy) dispatch_block_t cancellation;
@property (nonatomic) BOOL                   cancelled;
@end

@implementation BrandingRequestToken

- (void)cancel
{
    dispatch_block_t cancellation;
    @synchronized(self)
    {
        if (self.cancelled)
            return;
        self.cancelled    = YES;
        cancellation      = [self.cancellation copy];
        self.cancellation = nil;
    }
    if (cancellation)
        cancellation();
}

- (BOOL)isCancelled
{
    @synchronized(self)
    {
        return self.cancelled;
    }
}

- (void)dealloc
{
    [self cancel];
}

@end

@interface                                          BrandingWaiter : NSObject
@property (nonatomic, copy) BrandingCompletion      completion;
@property (nonatomic, strong) BrandingRequestToken *token;
@end

@implementation BrandingWaiter
@end

@interface                                          ThumbnailWaiter : NSObject
@property (nonatomic, copy) ThumbnailCompletion     completion;
@property (nonatomic, strong) BrandingRequestToken *token;
@end

@implementation ThumbnailWaiter
@end

@interface                                                                BrandingClient ()
@property (nonatomic, strong) NSURLSession                               *session;
@property (nonatomic, strong) dispatch_queue_t                            stateQueue;
@property (nonatomic, strong) NSCache<NSString *, BrandingCacheEntry *>  *cache;
@property (nonatomic, strong) NSCache<NSString *, ThumbnailCacheEntry *> *thumbnailCache;
@property (nonatomic, strong)
    NSMutableDictionary<NSString *, NSMutableArray<BrandingWaiter *> *>               *waiters;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *tasks;
@property (nonatomic, strong)
    NSMutableDictionary<NSString *, NSMutableArray<ThumbnailWaiter *> *> *thumbnailWaiters;
@property (nonatomic, strong)
    NSMutableDictionary<NSString *, NSURLSessionDataTask *> *thumbnailTasks;
@end

static NSString *const BrandingErrorDomain = @"dev.adrian.dearrow.branding";

static NSError *BrandingError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:BrandingErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

static NSString *ValidVideoID(NSString *videoID)
{
    if (![videoID isKindOfClass:[NSString class]] || videoID.length != 11)
        return nil;
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:
                            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    if ([videoID rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound)
        return nil;
    return videoID;
}

static BOOL ValidTitleEntry(NSDictionary *entry)
{
    if (![entry isKindOfClass:[NSDictionary class]] || [entry[@"original"] boolValue])
        return NO;
    NSString *title = entry[@"title"];
    if (![title isKindOfClass:[NSString class]] ||
        [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                .length == 0)
        return NO;
    id votes = entry[@"votes"];
    return [entry[@"locked"] boolValue] || ![votes respondsToSelector:@selector(integerValue)] ||
           [votes integerValue] >= 0;
}

static NSDictionary *FirstValidTitle(NSArray *entries)
{
    if (![entries isKindOfClass:[NSArray class]])
        return nil;
    for (id entry in entries)
    {
        if (ValidTitleEntry(entry))
            return entry;
    }
    return nil;
}

static NSURL *ThumbnailURL(NSString *videoID)
{
    NSURLComponents *components = [NSURLComponents
        componentsWithString:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail"];
    components.queryItems       = @[ [NSURLQueryItem queryItemWithName:@"videoID" value:videoID] ];
    return components.URL;
}

static NSURLRequest *BrandingRequest(NSURL *URL, NSString *accept, NSTimeInterval timeout)
{
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:URL
                                cachePolicy:NSURLRequestUseProtocolCachePolicy
                            timeoutInterval:timeout];
    [request setValue:accept forHTTPHeaderField:@"Accept"];
    [request setValue:@"DeArrow" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"DeArrow" forHTTPHeaderField:@"x-client-name"];
    return request;
}

@implementation BrandingClient

+ (instancetype)sharedClient
{
    static BrandingClient *client;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ client = [self new]; });
    return client;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        NSURLSessionConfiguration *configuration =
            [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest  = 8.0;
        configuration.timeoutIntervalForResource = 12.0;
        _session    = [NSURLSession sessionWithConfiguration:configuration];
        _stateQueue = dispatch_queue_create("dev.adrian.dearrow.branding", DISPATCH_QUEUE_SERIAL);
        _cache      = [NSCache new];
        _cache.countLimit          = 512;
        _thumbnailCache            = [NSCache new];
        _thumbnailCache.countLimit = 256;
        _waiters                   = [NSMutableDictionary dictionary];
        _tasks                     = [NSMutableDictionary dictionary];
        _thumbnailWaiters          = [NSMutableDictionary dictionary];
        _thumbnailTasks            = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BrandingRecord *)cachedBrandingForVideoID:(NSString *)videoID
{
    NSString *validID = ValidVideoID(videoID);
    if (!validID)
        return nil;
    BrandingCacheEntry *entry = [self.cache objectForKey:validID];
    if (entry.expiresAt.timeIntervalSinceNow > 0)
        return entry.record;
    if (entry)
        [self.cache removeObjectForKey:validID];
    return nil;
}

- (BrandingRequestToken *)requestBrandingForVideoID:(NSString *)videoID
                                         completion:(BrandingCompletion)completion
{
    NSString             *validID = ValidVideoID(videoID);
    BrandingRequestToken *token   = [BrandingRequestToken new];
    if (!validID || !completion)
        return token;

    __weak BrandingRequestToken *weakToken = token;
    __weak typeof(self)          weakSelf  = self;
    token.cancellation                     = ^{
        __strong typeof(weakSelf) self        = weakSelf;
        BrandingRequestToken     *strongToken = weakToken;
        if (!self || !strongToken)
            return;
        dispatch_async(self.stateQueue, ^{
            NSMutableArray<BrandingWaiter *> *waiters = self.waiters[validID];
            BrandingWaiter                   *matchedWaiter;
            for (BrandingWaiter *waiter in waiters.copy)
            {
                if (waiter.token == strongToken)
                {
                    matchedWaiter = waiter;
                    break;
                }
            }
            if (matchedWaiter)
                [waiters removeObject:matchedWaiter];
            if (waiters.count == 0)
            {
                [self.waiters removeObjectForKey:validID];
                [self.tasks[validID] cancel];
                [self.tasks removeObjectForKey:validID];
            }
        });
    };

    dispatch_async(self.stateQueue, ^{
        if ([token isCancelled])
            return;
        BrandingCacheEntry *entry = [self.cache objectForKey:validID];
        if (entry.expiresAt.timeIntervalSinceNow > 0)
        {
            BrandingRecord *record = entry.record;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![token isCancelled])
                    completion(record, nil);
            });
            return;
        }
        if (entry)
            [self.cache removeObjectForKey:validID];

        BrandingWaiter *waiter                    = [BrandingWaiter new];
        waiter.completion                         = [completion copy];
        waiter.token                              = token;
        NSMutableArray<BrandingWaiter *> *waiters = self.waiters[validID];
        if (!waiters)
        {
            waiters               = [NSMutableArray array];
            self.waiters[validID] = waiters;
        }
        [waiters addObject:waiter];
        if (self.tasks[validID])
            return;

        NSURLComponents *components =
            [NSURLComponents componentsWithString:@"https://sponsor.ajay.app/api/branding"];
        components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"videoID" value:validID] ];
        NSURLRequest         *request = BrandingRequest(components.URL, @"application/json", 8.0);
        NSURLSessionDataTask *task    = [self.session
            dataTaskWithRequest:request
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                  [self finishVideoID:validID data:data response:response error:error];
              }];
        self.tasks[validID]           = task;
        [task resume];
    });
    return token;
}

- (void)finishVideoID:(NSString *)videoID
                 data:(NSData *)data
             response:(NSURLResponse *)response
                error:(NSError *)error
{
    dispatch_async(self.stateQueue, ^{
        [self.tasks removeObjectForKey:videoID];
        NSArray<BrandingWaiter *> *waiters = self.waiters[videoID].copy;
        [self.waiters removeObjectForKey:videoID];
        BrandingRecord *record;
        NSError        *resultError = error;
        NSInteger       statusCode  = [(NSHTTPURLResponse *) response statusCode];
        BOOL            cacheResult = NO;
        if (!resultError && statusCode == 404)
        {
            resultError = nil;
            cacheResult = YES;
        }
        else if (!resultError && statusCode != 200)
        {
            resultError = BrandingError(statusCode, @"Branding request failed");
        }
        else if (!resultError && data.length == 0)
        {
            resultError = BrandingError(1, @"Branding response was empty");
        }
        else if (!resultError)
        {
            NSError *jsonError;
            id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (![root isKindOfClass:[NSDictionary class]])
                resultError = jsonError ?: BrandingError(1, @"Branding response was not an object");
            if (!resultError)
            {
                cacheResult              = YES;
                NSDictionary *titleEntry = FirstValidTitle(root[@"titles"]);
                NSArray      *thumbnails = root[@"thumbnails"];
                BOOL          hasThumbnail =
                    [thumbnails isKindOfClass:[NSArray class]] && thumbnails.count > 0;
                NSString *title =
                    [titleEntry[@"title"] isKindOfClass:[NSString class]]
                        ? [titleEntry[@"title"]
                              stringByTrimmingCharactersInSet:[NSCharacterSet
                                                                  whitespaceAndNewlineCharacterSet]]
                        : nil;
                if (title || hasThumbnail)
                    record = [[BrandingRecord alloc]
                        initWithVideoID:videoID
                                  title:title
                           thumbnailURL:hasThumbnail ? ThumbnailURL(videoID) : nil];
            }
        }
        if (cacheResult)
        {
            BrandingCacheEntry *entry = [BrandingCacheEntry new];
            entry.record              = record;
            entry.expiresAt = [NSDate dateWithTimeIntervalSinceNow:record ? 3600.0 : 180.0];
            [self.cache setObject:entry forKey:videoID];
        }
        for (BrandingWaiter *waiter in waiters)
        {
            BrandingCompletion    completion = waiter.completion;
            BrandingRequestToken *token      = waiter.token;
            if (!completion || [token isCancelled])
                continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![token isCancelled])
                    completion(record, resultError);
            });
        }
    });
}

- (BrandingRequestToken *)requestThumbnailForVideoID:(NSString *)videoID
                                          completion:(ThumbnailCompletion)completion
{
    NSString             *validID = ValidVideoID(videoID);
    BrandingRequestToken *token   = [BrandingRequestToken new];
    if (!validID || !completion)
        return token;

    __weak BrandingRequestToken *weakToken = token;
    __weak typeof(self)          weakSelf  = self;
    token.cancellation                     = ^{
        __strong typeof(weakSelf) self        = weakSelf;
        BrandingRequestToken     *strongToken = weakToken;
        if (!self || !strongToken)
            return;
        dispatch_async(self.stateQueue, ^{
            NSMutableArray<ThumbnailWaiter *> *waiters = self.thumbnailWaiters[validID];
            ThumbnailWaiter                   *matchedWaiter;
            for (ThumbnailWaiter *waiter in waiters.copy)
            {
                if (waiter.token == strongToken)
                {
                    matchedWaiter = waiter;
                    break;
                }
            }
            if (matchedWaiter)
                [waiters removeObject:matchedWaiter];
            if (waiters.count == 0)
            {
                [self.thumbnailWaiters removeObjectForKey:validID];
                [self.thumbnailTasks[validID] cancel];
                [self.thumbnailTasks removeObjectForKey:validID];
            }
        });
    };

    dispatch_async(self.stateQueue, ^{
        if ([token isCancelled])
            return;
        ThumbnailCacheEntry *entry = [self.thumbnailCache objectForKey:validID];
        if (entry.expiresAt.timeIntervalSinceNow > 0)
        {
            UIImage *cachedImage = entry.negative ? nil : entry.image;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![token isCancelled])
                    completion(cachedImage, nil);
            });
            return;
        }
        if (entry)
            [self.thumbnailCache removeObjectForKey:validID];
        ThumbnailWaiter *waiter                    = [ThumbnailWaiter new];
        waiter.completion                          = [completion copy];
        waiter.token                               = token;
        NSMutableArray<ThumbnailWaiter *> *waiters = self.thumbnailWaiters[validID];
        if (!waiters)
        {
            waiters                        = [NSMutableArray array];
            self.thumbnailWaiters[validID] = waiters;
        }
        [waiters addObject:waiter];
        if (self.thumbnailTasks[validID])
            return;
        NSURL                *URL     = ThumbnailURL(validID);
        NSURLRequest         *request = BrandingRequest(URL, @"image/*", 12.0);
        NSURLSessionDataTask *task    = [self.session
            dataTaskWithRequest:request
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                  [self finishThumbnailVideoID:validID data:data response:response error:error];
              }];
        self.thumbnailTasks[validID]  = task;
        [task resume];
    });
    return token;
}

- (void)finishThumbnailVideoID:(NSString *)videoID
                          data:(NSData *)data
                      response:(NSURLResponse *)response
                         error:(NSError *)error
{
    dispatch_async(self.stateQueue, ^{
        [self.thumbnailTasks removeObjectForKey:videoID];
        NSArray<ThumbnailWaiter *> *waiters = self.thumbnailWaiters[videoID].copy;
        [self.thumbnailWaiters removeObjectForKey:videoID];
        UIImage  *image;
        NSError  *resultError    = error;
        NSInteger statusCode     = [(NSHTTPURLResponse *) response statusCode];
        BOOL      negativeResult = NO;
        if (!resultError && statusCode == 404)
            negativeResult = YES;
        else if (!resultError && statusCode != 200)
            resultError = BrandingError(statusCode, @"Thumbnail request failed");
        if (!resultError && data.length > 0)
            image = [UIImage imageWithData:data];
        if (!image && !resultError)
            negativeResult = YES;
        if (image)
        {
            ThumbnailCacheEntry *entry = [ThumbnailCacheEntry new];
            entry.image                = image;
            entry.expiresAt            = [NSDate dateWithTimeIntervalSinceNow:3600.0];
            [self.thumbnailCache setObject:entry forKey:videoID];
        }
        else if (negativeResult)
        {
            ThumbnailCacheEntry *entry = [ThumbnailCacheEntry new];
            entry.negative             = YES;
            entry.expiresAt            = [NSDate dateWithTimeIntervalSinceNow:180.0];
            [self.thumbnailCache setObject:entry forKey:videoID];
            resultError = nil;
        }
        for (ThumbnailWaiter *waiter in waiters)
        {
            ThumbnailCompletion   completion = waiter.completion;
            BrandingRequestToken *token      = waiter.token;
            if (!completion || [token isCancelled])
                continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![token isCancelled])
                    completion(image, resultError);
            });
        }
    });
}

- (void)clearCache
{
    dispatch_async(self.stateQueue, ^{
        for (NSArray<BrandingWaiter *> *waiters in self.waiters.allValues)
        {
            for (BrandingWaiter *waiter in waiters)
                [waiter.token cancel];
        }
        for (NSArray<ThumbnailWaiter *> *waiters in self.thumbnailWaiters.allValues)
        {
            for (ThumbnailWaiter *waiter in waiters)
                [waiter.token cancel];
        }
        for (NSURLSessionDataTask *task in self.tasks.allValues)
            [task cancel];
        [self.tasks removeAllObjects];
        [self.waiters removeAllObjects];
        [self.cache removeAllObjects];
        for (NSURLSessionDataTask *task in self.thumbnailTasks.allValues)
            [task cancel];
        [self.thumbnailTasks removeAllObjects];
        [self.thumbnailWaiters removeAllObjects];
        [self.thumbnailCache removeAllObjects];
    });
}

@end
