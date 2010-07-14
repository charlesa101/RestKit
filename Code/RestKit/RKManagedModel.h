//
// RKManagedModel.h
//  RestKit
//
//  Created by Blake Watters on 8/14/09.
//  Copyright 2009 Two Toasters. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "RKModelMappableProtocol.h"
#import "RKModelManager.h"

@class RKManagedModel;

/////////////////////////////////////////////////////////////////////////////////////////////////
// Object Cacheing Support
 	
@protocol RKManagedModelObjectCache

/**
 * Return a set of objects locally cached in the Core Data store for a given
 * resource path. The default implementation does nothing, subclasses are responsible
 * for parsing the object path and querying the managed object context.
 */ 	
+ (NSArray*)objectsForResourcePath:(NSString*)resourcePath;
 		 	
@end

/////////////////////////////////////////////////////////////////////////////////////////////////
// RestKit managed models

@interface RKManagedModel : NSManagedObject <RKModelMappable, RKManagedModelObjectCache> {
	
}

/**
 * The Core Data managed object context from the RKModelManager's objectStore
 * that is managing this model
 */
+ (NSManagedObjectContext*)managedObjectContext;

/**
 *	The NSEntityDescription for the Subclass 
 *	defaults to the subclass className, may be overridden
 */
+ (NSEntityDescription*)entity;

/**
 *	Returns an initialized NSFetchRequest for the entity, with no predicate
 */
+ (NSFetchRequest*)request;

+ (NSArray*)objectsWithRequest:(NSFetchRequest*)request;
+ (id)objectWithRequest:(NSFetchRequest*)request;
+ (NSArray*)objectsWithPredicate:(NSPredicate*)predicate;
+ (id)objectWithPredicate:(NSPredicate*)predicate;
+ (NSArray*)allObjects;

// Count the objects of this class in the store...
+ (NSUInteger)count;

/**
 *	Creates a new OTManagedModel and inserts it into the managedObjectContext.
 */
+ (id)newObject;

/**
 *	Retrieves a model object from the appropriate context using the objectId
 */
+ (NSManagedObject*)objectWithId:(NSManagedObjectID*)objectId;

/**
 *	Retrieves a array of model objects from the appropriate context using
 *	an array of NSManagedObjectIDs
 */
+ (NSArray*)objectsWithIds:(NSArray*)objectIds;

+ (NSManagedObjectID*)idWithObject:(NSManagedObject*)object;
+ (NSArray*)idsWithObjects:(NSArray*)objects;

/**
 *	The primaryKey property mapping, defaults to @"railsID"
 */
+ (NSString*)primaryKey;

/**
 * The name of the primary key in the server-side data payload. Defaults to @"id" for Rails generated XML/JSON
 */
+ (NSString*)primaryKeyElement;

/**
 *	Will find the existing object with the primary key of 'value' and return it
 *	or return nil
 */
+ (id)findByPrimaryKey:(id)value;

/**
 *	Defines the properties which the OTModelMapper maps elements to
 */
+ (NSDictionary*)elementToPropertyMappings;

/**
 *	Defines the relationship properties which the OTModelMapper maps elements to
 *	@"user" => @"user" will map the @"user" element to an NSObject* property @"user"
 *	@"memberships > user" => @"users"   will map the @"user" elements in the @"memberships" element
 *				to an NSSet* property named @"users"
 */
+ (NSDictionary*)elementToRelationshipMappings;

/**
 * Returns all the XML/JSON element names for the properties of this model
 */
+ (NSArray*)elementNames;

/**
 * Returns all the Managed Model property names of this model
 */
+ (NSArray*)elementNames;

// The server side name of the model?
// TODO: Should be registered on the model manager somehow...
// TODO: Use entity name on managed model?
+ (NSString*)modelName;

/**
 * Formats an element name to match the encoding format of a mapping request. By default, assumes
 * that the element name should be dasherized for XML and underscored for JSON
 */
+ (NSString*)formatElementName:(NSString*)elementName forMappingFormat:(RKMappingFormat)format;

/**
 * Returns an array of fetch requests used for querying locally cached objects in the Core Data
 * store for a given resource path. The default implementation does nothing, so subclasses
 * are responsible for parsing the object path and building a valid array of fetch requests.
 */
//+ (NSArray*)fetchRequestsForResourcePath:(NSString*)resourcePath;

- (NSDictionary*)elementNamesAndPropertyValues;

@end
