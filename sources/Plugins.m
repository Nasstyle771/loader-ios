#import "Plugins.h"

@implementation Plugins
static NSMutableArray *plugins = nil;

+ (NSString *)makeJSON
{
    return [Utilities JSONStringFromObject:plugins options:0 fallback:@"[]"];
}

static NSDictionary *parseJSMetadata(NSString *code, NSString *defaultName)
{
    NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
    manifest[@"name"]        = defaultName;
    manifest[@"description"] = @"";
    manifest[@"version"]     = @"1.0.0";
    manifest[@"authors"]     = @[ @"Unknown" ];

    if (!code || code.length == 0) return manifest;

    // Check for JSON META header: /* @META { ... } */ or // META { ... }
    NSRegularExpression *metaRegex = [NSRegularExpression regularExpressionWithPattern:@"(?:\\/\\*\\s*@META|\\/\\/\\s*META)\\s*(\\{.*?\\})"
                                                                               options:NSRegularExpressionDotMatchesLineSeparators
                                                                                 error:nil];
    NSTextCheckingResult *metaMatch = [metaRegex firstMatchInString:code options:0 range:NSMakeRange(0, MIN((NSUInteger)2048, code.length))];
    if (metaMatch && metaMatch.numberOfRanges > 1)
    {
        NSString *jsonStr = [code substringWithRange:[metaMatch rangeAtIndex:1]];
        NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        if (jsonData)
        {
            NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if ([parsed isKindOfClass:[NSDictionary class]])
            {
                [manifest addEntriesFromDictionary:parsed];
                return manifest;
            }
        }
    }

    // Line-by-line comment parsing (@name, @description, @version, @author)
    NSArray<NSString *> *lines = [code componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSUInteger maxLines = MIN((NSUInteger)40, lines.count);

    for (NSUInteger i = 0; i < maxLines; i++)
    {
        NSString *line = lines[i];
        if ([line containsString:@"@name "])
        {
            NSArray *parts = [line componentsSeparatedByString:@"@name "];
            if (parts.count > 1) manifest[@"name"] = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        else if ([line containsString:@"@description "])
        {
            NSArray *parts = [line componentsSeparatedByString:@"@description "];
            if (parts.count > 1) manifest[@"description"] = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        else if ([line containsString:@"@version "])
        {
            NSArray *parts = [line componentsSeparatedByString:@"@version "];
            if (parts.count > 1) manifest[@"version"] = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        else if ([line containsString:@"@author "])
        {
            NSArray *parts = [line componentsSeparatedByString:@"@author "];
            if (parts.count > 1) manifest[@"authors"] = @[[parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
    }

    return manifest;
}

+ (void)init
{
    plugins = [[NSMutableArray alloc] init];

    [LoaderShared
        scanAddonDirectory:@"Plugins"
                  category:LOG_CATEGORY_PLUGINS
                   handler:^(NSString *folder, NSString *dir) {
                       // 1. Single .js file plugin support (e.g. Documents/Unbound/Plugins/PluginName.js)
                       if (![FileSystem isDirectory:dir])
                       {
                           if ([folder hasSuffix:@".js"])
                           {
                               NSString *pluginName = [folder stringByDeletingPathExtension];
                               NSData *bundleData = [FileSystem readFile:dir];
                               NSString *bundleStr = [[NSString alloc] initWithData:bundleData encoding:NSUTF8StringEncoding];
                               
                               if (bundleStr.length > 0)
                               {
                                   NSMutableDictionary *manifest = [parseJSMetadata(bundleStr, pluginName) mutableCopy];
                                   manifest[@"folder"] = pluginName;
                                   manifest[@"path"]   = dir;
                                   manifest[@"entry"]  = dir;
                                   manifest[@"main"]   = folder;

                                   [plugins addObject:@{
                                       @"manifest" : manifest,
                                       @"bundle" : bundleStr
                                   }];

                                   [Logger info:LOG_CATEGORY_PLUGINS
                                         format:@"Loaded single-file plugin %@ from %@.", pluginName, dir];
                               }
                           }
                           else
                           {
                               [Logger info:LOG_CATEGORY_PLUGINS
                                     format:@"Skipping non-plugin file %@.", folder];
                           }
                           return;
                       }

                       // 2. Folder-based plugin with manifest.json
                       NSString *manifestPath = [NSString pathWithComponents:@[ dir, @"manifest.json" ]];
                       NSMutableDictionary *manifest = nil;

                       if ([FileSystem exists:manifestPath])
                       {
                           manifest = [LoaderShared parseManifestAt:manifestPath
                                                             folder:folder
                                                           category:LOG_CATEGORY_PLUGINS];
                       }

                       NSString *entry = nil;
                       if (manifest)
                       {
                           entry = [LoaderShared resolveManifestEntryInDirectory:dir
                                                                        manifest:manifest
                                                                             key:@"main"];
                       }
                       else
                       {
                           // 3. Folder-based plugin without manifest (e.g. index.js / plugin.js / main.js)
                           NSArray<NSString *> *entryCandidates = @[ @"index.js", @"plugin.js", @"main.js", @"bundle.js", [NSString stringWithFormat:@"%@.js", folder] ];
                           for (NSString *candidate in entryCandidates)
                           {
                               NSString *candidatePath = [NSString pathWithComponents:@[ dir, candidate ]];
                               if ([FileSystem exists:candidatePath] && ![FileSystem isDirectory:candidatePath])
                               {
                                   entry = candidatePath;
                                   break;
                               }
                           }

                           if (entry)
                           {
                               NSData *candidateData = [FileSystem readFile:entry];
                               NSString *candidateStr = [[NSString alloc] initWithData:candidateData encoding:NSUTF8StringEncoding];
                               manifest = [parseJSMetadata(candidateStr, folder) mutableCopy];
                           }
                       }

                       if (!entry || !manifest)
                       {
                           [Logger info:LOG_CATEGORY_PLUGINS
                                 format:@"Skipping %@ as entry point could not be resolved.", folder];
                           return;
                       }

                       NSData *bundle = [FileSystem readFile:entry];
                       if (bundle.length == 0)
                       {
                           return;
                       }

                       manifest[@"folder"] = folder;
                       manifest[@"path"]   = dir;
                       manifest[@"entry"]  = entry;

                       [plugins addObject:@{
                           @"manifest" : manifest,
                           @"bundle" : [[NSString alloc] initWithData:bundle
                                                             encoding:NSUTF8StringEncoding]
                       }];

                       [Logger info:LOG_CATEGORY_PLUGINS
                             format:@"Loaded plugin %@ from %@.", folder, entry];
                   }];

    NSUInteger pluginCount = [plugins count];
    NSString  *pluralForm  = (pluginCount == 1) ? @"plugin" : @"plugins";
    [Logger info:LOG_CATEGORY_PLUGINS format:@"Loaded %lu %@.", pluginCount, pluralForm];
}

@end
