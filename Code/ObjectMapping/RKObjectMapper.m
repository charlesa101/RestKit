//
//  RKObjectMapper.m
//  RestKit
//
//  Created by Blake Watters on 3/4/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#import <objc/message.h>
// TODO: Factor out Core Data...
#import <CoreData/CoreData.h>

#import "RKObjectMapper.h"
#import "NSDictionary+RKAdditions.h"
#import "RKJSONParser.h"
#import "Errors.h"

// Default format string for date and time objects from Rails
// TODO: Rails specifics should probably move elsewhere...
static const NSString* kRKModelMapperRailsDateTimeFormatString = @"yyyy-MM-dd'T'HH:mm:ss'Z'"; // 2009-08-08T17:23:59Z
static const NSString* kRKModelMapperRailsDateFormatString = @"MM/dd/yyyy";
static const NSString* kRKModelMapperMappingFormatParserKey = @"RKMappingFormatParser";

@interface RKObjectMapper (Private)

- (id)parseString:(NSString*)string;
- (void)updateModel:(id)model fromElements:(NSDictionary*)elements;

- (Class)typeClassForProperty:(NSString*)property ofClass:(Class)class;
- (NSDictionary*)elementToPropertyMappingsForModel:(id)model;

- (id)findOrCreateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements;
- (id)createOrUpdateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements;

- (void)updateModel:(id)model ifNewPropertyValue:(id)propertyValue forPropertyNamed:(NSString*)propertyName; // Rename!
- (void)setPropertiesOfModel:(id)model fromElements:(NSDictionary*)elements;
- (void)setRelationshipsOfModel:(id)object fromElements:(NSDictionary*)elements;
- (void)updateModel:(id)model fromElements:(NSDictionary*)elements;

- (NSDate*)parseDateFromString:(NSString*)string;
- (NSDate*)dateInLocalTime:(NSDate*)date;

@end

@implementation RKObjectMapper

@synthesize format = _format;
@synthesize dateFormats = _dateFormats;
@synthesize remoteTimeZone = _remoteTimeZone;
@synthesize localTimeZone = _localTimeZone;
@synthesize errorsKeyPath = _errorsKeyPath;
@synthesize errorsConcatenationString = _errorsConcatenationString;

///////////////////////////////////////////////////////////////////////////////
// public

- (id)init {
	if (self = [super init]) {
		_elementToClassMappings = [[NSMutableDictionary alloc] init];
		_format = RKMappingFormatJSON;
		_inspector = [[RKObjectPropertyInspector alloc] init];
		self.dateFormats = [NSArray arrayWithObjects:kRKModelMapperRailsDateTimeFormatString, kRKModelMapperRailsDateFormatString, nil];
		self.remoteTimeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		self.localTimeZone = [NSTimeZone localTimeZone];
		self.errorsKeyPath = @"errors";
		self.errorsConcatenationString = @", ";
	}
	return self;
}

- (void)dealloc {
	[_elementToClassMappings release];
	[_inspector release];
	[_dateFormats release];
	[_errorsKeyPath release];
	[_errorsConcatenationString release];
	[super dealloc];
}

- (void)registerClass:(Class<RKObjectMappable>)aClass forElementNamed:(NSString*)elementName {
	[_elementToClassMappings setObject:aClass forKey:elementName];
}

- (void)setFormat:(RKMappingFormat)format {
	if (format == RKMappingFormatXML) {
		[NSException raise:@"No XML parser is available" format:@"RestKit does not currently have XML support. Use JSON."];
	}
	_format = format;
}

///////////////////////////////////////////////////////////////////////////////
// Mapping from a string

- (id)parseString:(NSString*)string {
	NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
	NSObject<RKParser>* parser = [threadDictionary objectForKey:kRKModelMapperMappingFormatParserKey];
	if (!parser) {
		if (_format == RKMappingFormatJSON) {
			parser = [[RKJSONParser alloc] init];
			[threadDictionary setObject:parser forKey:kRKModelMapperMappingFormatParserKey];
			[parser release];
		}
	}
	
	NSLog(@"Began parse...");
	id result = [parser objectFromString:string];
	NSLog(@"Finished parse...");
	return result;
}

- (NSError*)parseErrorFromString:(NSString*)string {
	NSString* errorMessage = [[[self parseString:string] valueForKeyPath:_errorsKeyPath] componentsJoinedByString:_errorsConcatenationString];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  errorMessage, NSLocalizedDescriptionKey,
							  nil];
	NSError *error = [NSError errorWithDomain:RKRestKitErrorDomain code:RKObjectLoaderRemoteSystemError userInfo:userInfo];
	
	return error;
}

- (id)mapFromString:(NSString*)string toClass:(Class)class keyPath:(NSString*)keyPath {
	id object = [self parseString:string];
	if (keyPath) {
		object = [object valueForKeyPath:keyPath];
	}
	if ([object isKindOfClass:[NSDictionary class]]) {
		return [self mapObjectFromDictionary:(NSDictionary*)object];
	} else if ([object isKindOfClass:[NSArray class]]) {
		if (class) {
			return [self mapObjectsFromArrayOfDictionaries:(NSArray*)object toClass:class];
		} else {
			return [self mapObjectsFromArrayOfDictionaries:(NSArray*)object];
		}
	} else if (nil == object) {
		NSLog(@"[RestKit] RKModelMapper: mapObject:fromString: attempted to map from a nil payload. Skipping...");
		return nil;
	} else {
		[NSException raise:@"Unable to map from requested string" 
					format:@"The object was deserialized into a %@. A dictionary or array of dictionaries was expected.", [object class]];
		return nil;
	}
}

- (id)mapFromString:(NSString*)string {
	return [self mapFromString:string toClass:nil keyPath:nil];
}

- (void)mapObject:(id)model fromString:(NSString*)string {
	id object = [self parseString:string];
	if ([object isKindOfClass:[NSDictionary class]]) {
		[self mapObject:model fromDictionary:object];
	} else if (nil == object) {
		NSLog(@"[RestKit] RKModelMapper: mapObject:fromString: attempted to map from a nil payload. Skipping...");
		return;
	} else {
		[NSException raise:@"Unable to map from requested string"
					format:@"The object was serialized into a %@. A dictionary of elements was expected.", [object class]];
	}
}

///////////////////////////////////////////////////////////////////////////////
// Mapping from objects

- (void)mapObject:(id)model fromDictionary:(NSDictionary*)dictionary {
	Class class = [model class];
	NSString* elementName = [_elementToClassMappings keyForObject:class];
	if (elementName) {
		NSDictionary* elements = [dictionary objectForKey:elementName];	
		[self updateModel:model fromElements:elements];
	} else {
		[NSException raise:@"Unable to map from requested dictionary"
					format:@"There was no mappable element found for objects of type %@", class];
	}
}

// TODO: Can I make this support keyPath??
- (id)mapObjectFromDictionary:(NSDictionary*)dictionary {
	NSString* elementName = [[dictionary allKeys] objectAtIndex:0];
	Class class = [_elementToClassMappings objectForKey:elementName];
	NSDictionary* elements = [dictionary objectForKey:elementName];
	
	id model = [self findOrCreateInstanceOfModelClass:class fromElements:elements];
	[self updateModel:model fromElements:elements];
	return model;
}

- (NSArray*)mapObjectsFromArrayOfDictionaries:(NSArray*)array {
	NSMutableArray* objects = [NSMutableArray array];
	for (NSDictionary* dictionary in array) {
		if (![dictionary isKindOfClass:[NSNull class]]) {
			// TODO: Makes assumptions about the structure of the JSON...
			NSString* elementName = [[dictionary allKeys] objectAtIndex:0];
			Class class = [_elementToClassMappings objectForKey:elementName];
			NSAssert(class != nil, @"Unable to perform object mapping without a destination class");
			NSDictionary* elements = [dictionary objectForKey:elementName];
			id object = [self createOrUpdateInstanceOfModelClass:class fromElements:elements];
			[objects addObject:object];
		}
	}
	
	return (NSArray*)objects;
}

// TODO: This form of mapping may need to be factored out... simple mapper / element mapper?
- (NSArray*)mapObjectsFromArrayOfDictionaries:(NSArray*)array toClass:(Class)class {
	NSMutableArray* objects = [NSMutableArray array];
	for (NSDictionary* dictionary in array) {
		if (![dictionary isKindOfClass:[NSNull class]]) {
			id object = [self createOrUpdateInstanceOfModelClass:class fromElements:dictionary];
			[objects addObject:object];
		}
	}
	
	return (NSArray*)objects;
}

///////////////////////////////////////////////////////////////////////////////
// Utility Methods

- (Class)typeClassForProperty:(NSString*)property ofClass:(Class)class {
	return [[_inspector propertyNamesAndTypesForClass:class] objectForKey:property];
}

- (NSDictionary*)elementToPropertyMappingsForModel:(id)model {
	return [[model class] elementToPropertyMappings];
}

///////////////////////////////////////////////////////////////////////////////
// Persistent Instance Finders

// TODO: This responsibility probaby belongs elsewhere...
- (id)findOrCreateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements {
	NSArray* objects = nil;
	id object = nil;
	
	if ([class respondsToSelector:@selector(allObjects)]) {
		NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
		
		if (nil == [threadDictionary objectForKey:class]) {
			NSFetchRequest* fetchRequest = [class fetchRequest];
			[fetchRequest setReturnsObjectsAsFaults:NO];			
			objects = [class objectsWithFetchRequest:fetchRequest];
			NSLog(@"Cacheing all %d %@ objects to thread local storage", [objects count], class);
			NSMutableDictionary* dictionary = [NSMutableDictionary dictionary];
			NSString* primaryKey = [class performSelector:@selector(primaryKey)];
			for (id theObject in objects) {			
				id primaryKeyValue = [theObject valueForKey:primaryKey];
				[dictionary setObject:theObject forKey:primaryKeyValue];
			}
			
			[threadDictionary setObject:dictionary forKey:class];
		}
		
		NSMutableDictionary* dictionary = [threadDictionary objectForKey:class];
		if ([class respondsToSelector:@selector(findByPrimaryKey:)]) {
			NSString* primaryKeyElement = [class performSelector:@selector(primaryKeyElement)];
			id primaryKeyValue = [elements objectForKey:primaryKeyElement];
			object = [dictionary objectForKey:primaryKeyValue];
		}
	}
	
	// instantiate if object is nil
	if (object == nil) {
		if ([class respondsToSelector:@selector(object)]) {
			object = [class object];
		} else {
			object = [[[class alloc] init] autorelease];
		}
	}
	
	return object;
}

- (id)createOrUpdateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements {
	id model = [self findOrCreateInstanceOfModelClass:class fromElements:elements];
	[self updateModel:model fromElements:elements];
	return model;
}

///////////////////////////////////////////////////////////////////////////////
// Property & Relationship Manipulation

- (void)updateModel:(id)model ifNewPropertyValue:(id)propertyValue forPropertyNamed:(NSString*)propertyName {	
	id currentValue = [model valueForKey:propertyName];
	if (nil == currentValue && nil == propertyValue) {
		// Don't set the property, both are nil
	} else if (nil == propertyValue || [propertyValue isKindOfClass:[NSNull class]]) {
		// Clear out the value to reset it
		[model setValue:nil forKey:propertyName];
	} else if (currentValue == nil || [currentValue isKindOfClass:[NSNull class]]) {
		// Existing value was nil, just set the property and be happy
		[model setValue:propertyValue forKey:propertyName];
	} else {
		SEL comparisonSelector;
		if ([propertyValue isKindOfClass:[NSString class]]) {
			comparisonSelector = @selector(isEqualToString:);
		} else if ([propertyValue isKindOfClass:[NSNumber class]]) {
			comparisonSelector = @selector(isEqualToNumber:);
		} else if ([propertyValue isKindOfClass:[NSDate class]]) {
			comparisonSelector = @selector(isEqualToDate:);
		} else if ([propertyValue isKindOfClass:[NSArray class]]) {
			comparisonSelector = @selector(isEqualToArray:);
		} else if ([propertyValue isKindOfClass:[NSDictionary class]]) {
			comparisonSelector = @selector(isEqualToDictionary:);
		} else {
			[NSException raise:@"NoComparisonSelectorFound" format:@"You need a comparison selector for %@ (%@)", propertyName, [propertyValue class]];
		}
		
		// Comparison magic using function pointers. See this page for details: http://www.red-sweater.com/blog/320/abusing-objective-c-with-class
		// Original code courtesy of Greg Parker
		// This is necessary because isEqualToNumber will return negative integer values that aren't coercable directly to BOOL's without help [sbw]
		BOOL (*ComparisonSender)(id, SEL, id) = (BOOL (*)(id, SEL, id)) objc_msgSend;		
		BOOL areEqual = ComparisonSender(currentValue, comparisonSelector, propertyValue);
		
		if (NO == areEqual) {
			[model setValue:propertyValue forKey:propertyName];
		}
	}
}

- (void)setPropertiesOfModel:(id)model fromElements:(NSDictionary*)elements {
	NSDictionary* elementToPropertyMappings = [self elementToPropertyMappingsForModel:model];
	for (NSString* elementKeyPath in elementToPropertyMappings) {		
		id elementValue = nil;		
		BOOL setValue = YES;
		
		@try {
			elementValue = [elements valueForKeyPath:elementKeyPath];
		}
		@catch (NSException * e) {
			NSLog(@"[RestKit] RKModelMapper: Unable to find element at keyPath %@ in elements dictionary for %@. Skipping...", elementKeyPath, [model class]);
			setValue = NO;
		}
		
		if (setValue) {
			id propertyValue = elementValue;
			NSString* propertyName = [elementToPropertyMappings objectForKey:elementKeyPath];
			Class class = [self typeClassForProperty:propertyName ofClass:[model class]];
			if (elementValue != (id)kCFNull && nil != elementValue) {
				if ([class isEqual:[NSDate class]]) {
					NSDate* date = [self parseDateFromString:(propertyValue)];
					propertyValue = [self dateInLocalTime:date];
				}
			}
			
			[self updateModel:model ifNewPropertyValue:propertyValue forPropertyNamed:propertyName];
		}
	}
}

- (void)setRelationshipsOfModel:(id)object fromElements:(NSDictionary*)elements {
	NSDictionary* elementToRelationshipMappings = [[object class] elementToRelationshipMappings];
	for (NSString* elementKeyPath in elementToRelationshipMappings) {
		NSString* propertyName = [elementToRelationshipMappings objectForKey:elementKeyPath];
		
		id relationshipElements = nil;
		@try {
			relationshipElements = [elements valueForKeyPath:elementKeyPath];
		}
		@catch (NSException* e) {
			NSLog(@"Caught exception:%@ when trying valueForKeyPath with path:%@ for elements:%@", e, elementKeyPath, elements);
		}
		
		if ([relationshipElements isKindOfClass:[NSArray class]] || [relationshipElements isKindOfClass:[NSSet class]]) {
			// NOTE: The last part of the keyPath contains the elementName for the mapped destination class of our children
			NSArray* componentsOfKeyPath = [elementKeyPath componentsSeparatedByString:@"."];
			Class class = [_elementToClassMappings objectForKey:[componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1]];
			NSMutableSet* children = [NSMutableSet setWithCapacity:[relationshipElements count]];
			for (NSDictionary* childElements in relationshipElements) {				
				id child = [self createOrUpdateInstanceOfModelClass:class fromElements:childElements];		
				if (child) {
					[children addObject:child];
				}
			}
			
			[object setValue:children forKey:propertyName];
		} else if ([relationshipElements isKindOfClass:[NSDictionary class]]) {
			NSArray* componentsOfKeyPath = [elementKeyPath componentsSeparatedByString:@"."];
			Class class = [_elementToClassMappings objectForKey:[componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1]];
			id child = [self createOrUpdateInstanceOfModelClass:class fromElements:relationshipElements];		
			[object setValue:child forKey:propertyName];
		}
	}
}

- (void)updateModel:(id)model fromElements:(NSDictionary*)elements {
	[self setPropertiesOfModel:model fromElements:elements];
	[self setRelationshipsOfModel:model fromElements:elements];
}

///////////////////////////////////////////////////////////////////////////////
// Date & Time Helpers

- (NSDate*)parseDateFromString:(NSString*)string {
	NSDate* date = nil;
	NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	// TODO: I changed this to local time and it fixes my date issues. wtf?
	[formatter setTimeZone:self.localTimeZone];
	for (NSString* formatString in self.dateFormats) {
		[formatter setDateFormat:formatString];
		date = [formatter dateFromString:string];
		if (date) {
			break;
		}
	}
	
	[formatter release];
	return date;
}

- (NSDate*)dateInLocalTime:(NSDate*)date {
	NSDate* destinationDate = nil;
	if (date) {
		NSInteger remoteGMTOffset = [self.remoteTimeZone secondsFromGMTForDate:date];
		NSInteger localGMTOffset = [self.localTimeZone secondsFromGMTForDate:date];
		NSTimeInterval interval = localGMTOffset - remoteGMTOffset;		
		destinationDate = [[[NSDate alloc] initWithTimeInterval:interval sinceDate:date] autorelease];
	}	
	return destinationDate;
}

@end
