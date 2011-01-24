#import "NSString-scopeSelector.h"
#import "ViBundle.h"
#import "logging.h"

@implementation ViBundle

@synthesize languages;
@synthesize commands;
@synthesize path;

+ (NSColor *)hashRGBToColor:(NSString *)hashRGB
{
	int r, g, b, a;
	const char *s = [hashRGB UTF8String];
	if (s == NULL)
		return nil;
	int rc = sscanf(s, "#%02X%02X%02X%02X", &r, &g, &b, &a);
	if (rc != 3 && rc != 4)
		return nil;
	if (rc == 3)
		a = 255;

	return [NSColor colorWithCalibratedRed:(float)r/255.0 green:(float)g/255.0 blue:(float)b/255.0 alpha:(float)a/255.0];
}

+ (void)normalizePreference:(NSDictionary *)preference intoDictionary:(NSMutableDictionary *)normalizedPreference
{
	NSDictionary *settings = [preference objectForKey:@"settings"];
	if (settings == nil) {
		INFO(@"missing settings dictionary in preference: %@", preference);
		return;
	}

	if (normalizedPreference == nil) {
		INFO(@"missing normalized preference dictionary in preference: %@", preference);
		return;
	}

	NSColor *color;
	NSString *value;

	/*
	 * Convert RGB color strings to actual color objects, with keys directly appropriate for NSAttributedStrings.
	 */
	if ((value = [settings objectForKey:@"foreground"]) != nil) {
		if ((color = [self hashRGBToColor:value]) != nil)
			[normalizedPreference setObject:color forKey:NSForegroundColorAttributeName];
	}

	if ((value = [settings objectForKey:@"background"]) != nil) {
		if ((color = [self hashRGBToColor:value]) != nil)
			[normalizedPreference setObject:color forKey:NSBackgroundColorAttributeName];
	}

	if ((value = [settings objectForKey:@"fontStyle"]) != nil) {
		if ([value rangeOfString:@"underline"].location != NSNotFound)
			[normalizedPreference setObject:[NSNumber numberWithInt:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName];
		if ([value rangeOfString:@"italic"].location != NSNotFound)
			[normalizedPreference setObject:[NSNumber numberWithFloat:0.3] forKey:NSObliquenessAttributeName];
		if ([value rangeOfString:@"bold"].location != NSNotFound)
			[normalizedPreference setObject:[NSNumber numberWithFloat:-3.0] forKey:NSStrokeWidthAttributeName];
	}
}

- (id)initWithPath:(NSString *)aPath
{
	self = [super init];
	if (self) {
		info = [NSDictionary dictionaryWithContentsOfFile:aPath];
		if ([info objectForKey:@"isDelta"]) {
			INFO(@"delta bundles not implemented, at %@", aPath);
			return nil;
		}

		languages = [[NSMutableArray alloc] init];
		preferences = [[NSMutableArray alloc] init];
		cachedPreferences = [[NSMutableDictionary alloc] init];
		uuids = [[NSMutableDictionary alloc] init];
		snippets = [[NSMutableArray alloc] init];
		commands = [[NSMutableArray alloc] init];
		path = [aPath stringByDeletingLastPathComponent];
	}

	return self;
}

- (NSString *)supportPath
{
	return [path stringByAppendingPathComponent:@"Support"];
}

- (NSString *)name
{
	return [info objectForKey:@"name"];
}

- (void)addLanguage:(ViLanguage *)lang
{
	[languages addObject:lang];
}

- (void)addPreferences:(NSMutableDictionary *)prefs
{
	[ViBundle normalizePreference:prefs intoDictionary:[prefs objectForKey:@"settings"]];
	[preferences addObject:prefs];
}

- (NSDictionary *)preferenceItems:(NSArray *)prefsNames
{
	NSMutableDictionary *prefsForScope = [[NSMutableDictionary alloc] init];

	NSDictionary *prefs;
	for (prefs in preferences) {
		NSDictionary *settings = [prefs objectForKey:@"settings"];

		NSMutableDictionary *prefsValues = nil;
		for (NSString *prefsName in prefsNames) {
			id prefsValue = [settings objectForKey:prefsName];
			if (prefsValue) {
				if (prefsValues == nil)
					prefsValues = [[NSMutableDictionary alloc] init];
				[prefsValues setObject:prefsValue forKey:prefsName];
			}
		}

		if (prefsValues) {
			NSString *scope = [prefs objectForKey:@"scope"];
			NSMutableDictionary *oldPrefsValues = [prefsForScope objectForKey:scope];
			if (oldPrefsValues)
				[oldPrefsValues addEntriesFromDictionary:prefsValues];
			else
				[prefsForScope setObject:prefsValues forKey:scope];
		}
	}

	return prefsForScope;
}

- (NSDictionary *)preferenceItem:(NSString *)prefsName
{
	NSMutableDictionary *prefsForScope = [[NSMutableDictionary alloc] init];

	NSDictionary *prefs;
	for (prefs in preferences) {
		NSDictionary *settings = [prefs objectForKey:@"settings"];
		id prefsValue = [settings objectForKey:prefsName];
		if (prefsValue) {
			NSString *scope = [prefs objectForKey:@"scope"];
			if (scope)
				[prefsForScope setObject:prefsValue forKey:scope];
		}
	}

	return prefsForScope;
}

- (void)addSnippet:(NSDictionary *)snippet
{
	[snippets addObject:snippet];
	
	NSString *uuid = [snippet objectForKey:@"uuid"];
	if (uuid == nil)
		uuid = [snippet objectForKey:@"bundleUUID"];

	if (uuid)
		[uuids setObject:snippet forKey:uuid];
	else
		INFO(@"missing bundleUUID in snippet %@", snippet);
}

- (void)addCommand:(NSMutableDictionary *)command
{
	[command setObject:self forKey:@"bundle"];
	[commands addObject:command];

	NSString *uuid = [command objectForKey:@"uuid"];
	if (uuid == nil)
		uuid = [command objectForKey:@"bundleUUID"];

	if (uuid)
		[uuids setObject:command forKey:uuid];
	else
		INFO(@"missing bundleUUID in command %@", command);
}

- (NSDictionary *)commandWithKey:(unichar)keycode andFlags:(unsigned int)flags matchingScopes:(NSArray *)scopes
{
	NSDictionary *command;
	for (command in commands) {

		NSString *key = [command objectForKey:@"keyEquivalent"];
		unichar keyEquiv = 0;
		NSUInteger modMask = 0;
		int i;
		for (i = 0; i < [key length]; i++) {
			unichar c = [key characterAtIndex:i];
			switch (c)
			{
			case '^':
				modMask |= NSControlKeyMask;
				break;
			case '@':
				modMask |= NSCommandKeyMask;
				break;
			case '~':
				modMask |= NSAlternateKeyMask;
				break;
			default:
				keyEquiv = c;
				break;
			}
		}

                if (keyEquiv != keycode || flags != modMask)
                	continue;

		if ([[command objectForKey:@"scope"] matchesScopes:scopes] > 0)
			return command;
	}

	return nil;
}

- (NSString *)tabTrigger:(NSString *)name matchingScopes:(NSArray *)scopes
{
        NSDictionary *snippet;
        for (snippet in snippets)
                if ([[snippet objectForKey:@"tabTrigger"] isEqualToString:name] &&
		    [[snippet objectForKey:@"scope"] matchesScopes:scopes] > 0)
			return [snippet objectForKey:@"content"];
        
        return nil;
}

- (NSMenu *)submenu:(NSDictionary *)menuLayout withName:(NSString *)name forScopes:(NSArray *)scopes
{
	int matches = 0;
	NSMenu *menu = [[NSMenu alloc] initWithTitle:name];
	NSDictionary *submenus = [menuLayout objectForKey:@"submenus"];

	for (NSString *uuid in [menuLayout objectForKey:@"items"]) {
		NSDictionary *command;
		NSMenuItem *item;

		if ([uuid isEqualToString:@"------------------------------------"]) {
			item = [NSMenuItem separatorItem];
			[menu addItem:item];
		} else if ((command = [uuids objectForKey:uuid]) != nil) {
			/*
			 * FIXME: move this code to a new ViBundleCommand class.
			 */
			NSString *key = [command objectForKey:@"keyEquivalent"];
			NSString *keyEquiv = @"";
			NSUInteger modMask = 0;
			int i;
			for (i = 0; i < [key length]; i++) {
				unichar c = [key characterAtIndex:i];
				switch (c)
				{
				case '^':
					modMask |= NSControlKeyMask;
					break;
				case '@':
					modMask |= NSCommandKeyMask;
					break;
				case '~':
					modMask |= NSAlternateKeyMask;
					break;
				default:
					keyEquiv = [NSString stringWithFormat:@"%C", c];
					break;
				}
			}

			SEL selector = NULL;
			if ([[command objectForKey:@"scope"] matchesScopes:scopes] > 0) {
				matches++;
				selector = @selector(performBundleCommand:);
			}

			item = [menu addItemWithTitle:[command objectForKey:@"name"]
                                               action:selector
                                        keyEquivalent:keyEquiv];
			[item setKeyEquivalentModifierMask:modMask];
			[item setRepresentedObject:command];
		} else {
			NSDictionary *submenuLayout = [submenus objectForKey:uuid];
			if (submenuLayout) {
				NSMenu *submenu = [self submenu:submenuLayout withName:[submenuLayout objectForKey:@"name"] forScopes:scopes];
				if (submenu) {
					item = [menu addItemWithTitle:[submenuLayout objectForKey:@"name"] action:NULL keyEquivalent:@""];
					[item setSubmenu:submenu];
				}
			} else
				DEBUG(@"missing menu item %@ in bundle %@", uuid, [self name]);
		}

	}

	return matches == 0 ? nil : menu;
}

- (NSMenu *)menuForScopes:(NSArray *)scopes
{
	NSDictionary *mainMenu = [info objectForKey:@"mainMenu"];
	if (mainMenu == nil)
		return nil;

	NSMenu *menu = [self submenu:mainMenu withName:[self name] forScopes:scopes];

	return menu;

}

@end

