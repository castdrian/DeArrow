#import "BrandingClient.h"

#import <UIKit/UIKit.h>

@interface BrandingCacheEntry : NSObject
@property(nonatomic, strong, nullable) BrandingRecord *record;
@property(nonatomic, strong) NSDate *expiresAt;
@end

@implementation BrandingCacheEntry
@end

@interface BrandingRequestToken ()
@property(nonatomic, copy) dispatch_block_t cancellation;
@end

@implementation BrandingRequestToken

- (void)cancel {
    dispatch_block_t cancellation = self.cancellation;
    self.cancellation = nil;
    if (cancellation)
        cancellation();
}

- (void)dealloc {
    [self cancel];
}

@end

@interface BrandingWaiter : NSObject
@property(nonatomic, copy) BrandingCompletion completion;
@property(nonatomic, weak) BrandingRequestToken *token;
@end

@implementation BrandingWaiter
@end

@interface ThumbnailWaiter : NSObject
@property(nonatomic, copy) ThumbnailCompletion completion;
@property(nonatomic, weak) BrandingRequestToken *token;
@end

@implementation ThumbnailWaiter
@end

@interface BrandingClient ()
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) dispatch_queue_t stateQueue;
@property(nonatomic, strong) NSCache<NSString *, BrandingCacheEntry *> *cache;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<BrandingWaiter *> *> *waiters;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *tasks;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<ThumbnailWaiter *> *> *thumbnailWaiters;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *thumbnailTasks;
@end

static NSString *const BrandingErrorDomain = @"dev.adrian.dearrow.branding";

static NSError *BrandingError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:BrandingErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *ValidVideoID(NSString *videoID) {
    if (![videoID isKindOfClass:[NSString class]] || videoID.length != 11)
        return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    if ([videoID rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound)
        return nil;
    return videoID;
}

static BOOL ValidTitleEntry(NSDictionary *entry) {
    if (![entry isKindOfClass:[NSDictionary class]] || [entry[@"original"] boolValue])
        return NO;
    NSString *title = entry[@"title"];
    if (![title isKindOfClass:[NSString class]] ||
        [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0)
        return NO;
    id votes = entry[@"votes"];
    return [entry[@"locked"] boolValue] || ![votes respondsToSelector:@selector(integerValue)] || [votes integerValue] >= 0;
}

static NSDictionary *FirstValidTitle(NSArray *entries) {
    if (![entries isKindOfClass:[NSArray class]])
        return nil;
    for (id entry in entries) {
        if (ValidTitleEntry(entry))
            return entry;
    }
    return nil;
}

static NSURL *ThumbnailURL(NSString *videoID) {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"videoID" value:videoID]];
    return components.URL;
}

static NSURLRequest *BrandingRequest(NSURL *URL, NSString *accept, NSTimeInterval timeout) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL
                                                              cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                          timeoutInterval:timeout];
    [request setValue:accept forHTTPHeaderField:@"Accept"];
    [request setValue:@"DeArrow" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"DeArrow" forHTTPHeaderField:@"x-client-name"];
    return request;
}

@implementation BrandingClient

+ (instancetype)sharedClient {
    static BrandingClient *client;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [self new];
    });
    return client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 8.0;
        configuration.timeoutIntervalForResource = 12.0;
        _session = [NSURLSession sessionWithConfiguration:configuration];
        _stateQueue = dispatch_queue_create("dev.adrian.dearrow.branding", DISPATCH_QUEUE_SERIAL);
        _cache = [NSCache new];
        _cache.countLimit = 512;
        _thumbnailCache = [NSCache new];
        _thumbnailCache.countLimit = 256;
        _waiters = [NSMutableDictionary dictionary];
        _tasks = [NSMutableDictionary dictionary];
        _thumbnailWaiters = [NSMutableDictionary dictionary];
        _thumbnailTasks = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BrandingRecord *)cachedBrandingForVideoID:(NSString *)videoID {
    NSString *validID = ValidVideoID(videoID);
    if (!validID)
        return nil;
    __block BrandingRecord *record;
    dispatch_sync(self.stateQueue, ^{
        BrandingCacheEntry *entry = [self.cache objectForKey:validID];
        if (entry.expiresAt.timeIntervalSinceNow > 0)
            record = entry.record;
        else if (entry)
            [self.cache removeObjectForKey:validID];
    });
    return record;
}

- (BrandingRequestToken *)requestBrandingForVideoID:(NSString *)videoID
                                         completion:(BrandingCompletion)completion {
    NSString *validID = ValidVideoID(videoID);
    BrandingRequestToken *token = [BrandingRequestToken new];
    if (!validID || !completion)
        return token;

    __weak BrandingRequestToken *weakToken = token;
    __weak typeof(self) weakSelf = self;
    token.cancellation = ^{
        __strong typeof(weakSelf) self = weakSelf;
        BrandingRequestToken *strongToken = weakToken;
        if (!self || !strongToken)
            return;
        dispatch_async(self.stateQueue, ^{
            NSMutableArray<BrandingWaiter *> *waiters = self.waiters[validID];
            BrandingWaiter *matchedWaiter;
            for (BrandingWaiter *waiter in waiters.copy) {
                if (waiter.token == strongToken) {
                    matchedWaiter = waiter;
                    break;
                }
            }
            if (matchedWaiter)
                [waiters removeObject:matchedWaiter];
            if (waiters.count == 0) {
                [self.waiters removeObjectForKey:validID];
                [self.tasks[validID] cancel];
                [self.tasks removeObjectForKey:validID];
            }
        });
    };

    dispatch_async(self.stateQueue, ^{
        BrandingCacheEntry *entry = [self.cache objectForKey:validID];
        if (entry.expiresAt.timeIntervalSinceNow > 0) {
            BrandingRecord *record = entry.record;
            dispatch_async(dispatch_get_main_queue(), ^{
                BrandingRequestToken *strongToken = weakToken;
                if (strongToken && strongToken.cancellation)
                    completion(record, nil);
            });
            return;
        }
        if (entry)
            [self.cache removeObjectForKey:validID];

        BrandingWaiter *waiter = [BrandingWaiter new];
        waiter.completion = [completion copy];
        waiter.token = token;
        NSMutableArray<BrandingWaiter *> *waiters = self.waiters[validID];
        if (!waiters) {
            waiters = [NSMutableArray array];
            self.waiters[validID] = waiters;
        }
        [waiters addObject:waiter];
        if (self.tasks[validID])
            return;

        NSURLComponents *components = [NSURLComponents componentsWithString:@"https://sponsor.ajay.app/api/branding"];
        components.queryItems = @[[NSURLQueryItem queryItemWithName:@"videoID" value:validID]];
        NSURLRequest *request = BrandingRequest(components.URL, @"application/json", 8.0);
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            [self finishVideoID:validID data:data response:response error:error];
        }];
        self.tasks[validID] = task;
        [task resume];
    });
    return token;
}

- (void)finishVideoID:(NSString *)videoID
                 data:(NSData *)data
             response:(NSURLResponse *)response
                error:(NSError *)error {
    dispatch_async(self.stateQueue, ^{
        [self.tasks removeObjectForKey:videoID];
        NSArray<BrandingWaiter *> *waiters = self.waiters[videoID].copy;
        [self.waiters removeObjectForKey:videoID];
        BrandingRecord *record;
        NSError *resultError = error;
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        BOOL cacheResult = NO;
        if (!resultError && statusCode == 404) {
            resultError = nil;
            cacheResult = YES;
        } else if (!resultError && statusCode != 200) {
            resultError = BrandingError(statusCode, @"Branding request failed");
        } else if (!resultError && data.length == 0) {
            resultError = BrandingError(1, @"Branding response was empty");
        } else if (!resultError) {
            NSError *jsonError;
            id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (![root isKindOfClass:[NSDictionary class]])
                resultError = jsonError ?: BrandingError(1, @"Branding response was not an object");
            if (!resultError) {
                cacheResult = YES;
                NSDictionary *titleEntry = FirstValidTitle(root[@"titles"]);
                NSArray *thumbnails = root[@"thumbnails"];
                BOOL hasThumbnail = [thumbnails isKindOfClass:[NSArray class]] && thumbnails.count > 0;
                NSString *title = [titleEntry[@"title"] isKindOfClass:[NSString class]]
                    ? [titleEntry[@"title"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                    : nil;
                if (title || hasThumbnail)
                    record = [[BrandingRecord alloc] initWithVideoID:videoID
                                                               title:title
                                                        thumbnailURL:hasThumbnail ? ThumbnailURL(videoID) : nil];
            }
        }
        if (cacheResult) {
            BrandingCacheEntry *entry = [BrandingCacheEntry new];
            entry.record = record;
            entry.expiresAt = [NSDate dateWithTimeIntervalSinceNow:record ? 3600.0 : 180.0];
            [self.cache setObject:entry forKey:videoID];
        }
        for (BrandingWaiter *waiter in waiters) {
            BrandingCompletion completion = waiter.completion;
            BrandingRequestToken *token = waiter.token;
            if (!completion || !token.cancellation)
                continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (token.cancellation)
                    completion(record, resultError);
            });
        }
    });
}

- (BrandingRequestToken *)requestThumbnailForVideoID:(NSString *)videoID
                                           completion:(ThumbnailCompletion)completion {
    NSString *validID = ValidVideoID(videoID);
    BrandingRequestToken *token = [BrandingRequestToken new];
    if (!validID || !completion)
        return token;

    __weak BrandingRequestToken *weakToken = token;
    __weak typeof(self) weakSelf = self;
    token.cancellation = ^{
        __strong typeof(weakSelf) self = weakSelf;
        BrandingRequestToken *strongToken = weakToken;
        if (!self || !strongToken)
            return;
        dispatch_async(self.stateQueue, ^{
            NSMutableArray<ThumbnailWaiter *> *waiters = self.thumbnailWaiters[validID];
            ThumbnailWaiter *matchedWaiter;
            for (ThumbnailWaiter *waiter in waiters.copy) {
                if (waiter.token == strongToken) {
                    matchedWaiter = waiter;
                    break;
                }
            }
            if (matchedWaiter)
                [waiters removeObject:matchedWaiter];
            if (waiters.count == 0) {
                [self.thumbnailWaiters removeObjectForKey:validID];
                [self.thumbnailTasks[validID] cancel];
                [self.thumbnailTasks removeObjectForKey:validID];
            }
        });
    };

    dispatch_async(self.stateQueue, ^{
        UIImage *cachedImage = [self.thumbnailCache objectForKey:validID];
        if (cachedImage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BrandingRequestToken *strongToken = weakToken;
                if (strongToken && strongToken.cancellation)
                    completion(cachedImage, nil);
            });
            return;
        }
        ThumbnailWaiter *waiter = [ThumbnailWaiter new];
        waiter.completion = [completion copy];
        waiter.token = token;
        NSMutableArray<ThumbnailWaiter *> *waiters = self.thumbnailWaiters[validID];
        if (!waiters) {
            waiters = [NSMutableArray array];
            self.thumbnailWaiters[validID] = waiters;
        }
        [waiters addObject:waiter];
        if (self.thumbnailTasks[validID])
            return;
        NSURL *URL = ThumbnailURL(validID);
        NSURLRequest *request = BrandingRequest(URL, @"image/*", 12.0);
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            [self finishThumbnailVideoID:validID data:data response:response error:error];
        }];
        self.thumbnailTasks[validID] = task;
        [task resume];
    });
    return token;
}

- (void)finishThumbnailVideoID:(NSString *)videoID
                           data:(NSData *)data
                       response:(NSURLResponse *)response
                          error:(NSError *)error {
    dispatch_async(self.stateQueue, ^{
        [self.thumbnailTasks removeObjectForKey:videoID];
        NSArray<ThumbnailWaiter *> *waiters = self.thumbnailWaiters[videoID].copy;
        [self.thumbnailWaiters removeObjectForKey:videoID];
        UIImage *image;
        NSError *resultError = error;
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (!resultError && statusCode != 200)
            resultError = BrandingError(statusCode, @"Thumbnail request failed");
        if (!resultError && data.length > 0)
            image = [UIImage imageWithData:data];
        if (!image && !resultError)
            resultError = BrandingError(2, @"Thumbnail response was not an image");
        if (image)
            [self.thumbnailCache setObject:image forKey:videoID];
        for (ThumbnailWaiter *waiter in waiters) {
            ThumbnailCompletion completion = waiter.completion;
            BrandingRequestToken *token = waiter.token;
            if (!completion || !token.cancellation)
                continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (token.cancellation)
                    completion(image, resultError);
            });
        }
    });
}

- (void)clearCache {
    dispatch_async(self.stateQueue, ^{
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
