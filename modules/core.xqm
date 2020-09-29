xquery version "3.1";

(:~
 : Core functions of the WeGA-WebApp
 :)
module namespace core="http://xquery.weber-gesamtausgabe.de/modules/core";
declare default collation "?lang=de;strength=primary";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace mei="http://www.music-encoding.org/ns/mei";
declare namespace request="http://exist-db.org/xquery/request";
declare namespace xmldb="http://exist-db.org/xquery/xmldb";
declare namespace util="http://exist-db.org/xquery/util";

import module namespace config="http://xquery.weber-gesamtausgabe.de/modules/config" at "config.xqm";
import module namespace norm="http://xquery.weber-gesamtausgabe.de/modules/norm" at "norm.xqm";
import module namespace wdt="http://xquery.weber-gesamtausgabe.de/modules/wdt" at "wdt.xqm";
import module namespace mycache="http://xquery.weber-gesamtausgabe.de/modules/cache" at "xmldb:exist:///db/apps/WeGA-WebApp-lib/xquery/cache.xqm";
import module namespace date="http://xquery.weber-gesamtausgabe.de/modules/date" at "xmldb:exist:///db/apps/WeGA-WebApp-lib/xquery/date.xqm";
import module namespace str="http://xquery.weber-gesamtausgabe.de/modules/str" at "xmldb:exist:///db/apps/WeGA-WebApp-lib/xquery/str.xqm";

(:~
 : Get document by ID
 : The core:doc() function will also resolve duplicates
 :
 : @author Peter Stadler
 : @param $docID the ID of the document
 : @return returns the document node of the resource found for the specified ID.
:)
declare function core:doc($docID as xs:string) as document-node()? {
    let $collectionPath := config:getCollectionPath($docID)
    let $docURL := str:join-path-elements(($collectionPath, $docID)) || '.xml'
    return 
        if(doc-available($docURL)) then
            let $doc := doc($docURL) 
            return
                if($doc/*/*:ref/@target) then core:doc($doc/*/*:ref/@target)
                else $doc
        else if($config:isDevelopment) then core:logToFile('debug', 'core:doc(): unable to open ' || $docID)
        else ()
};

(:~
 : Returns collection from the WeGA-data library
 : In contrast to core:getOrCreateColl() this function will return *all* documents from the specified collection, i.e. with all duplicates
 :
 : @author Peter Stadler
 : @param $collectionName the name of the collection
 : @return document-node()*
 :)
declare function core:data-collection($collectionName as xs:string) as document-node()* {
    let $collectionPath := str:join-path-elements(($config:data-collection-path, $collectionName)) 
    let $collectionPathExists := xmldb:collection-available($collectionPath) and ($collectionPath ne '')
    return 
        if ($collectionPathExists) then collection($collectionPath)
        else ()
};

(:~
 : Returns collection (from cache, if possible)
 : In contrast to core:data-collection() this function will return the filtered (i.e. without duplicates) and sorted documents from the specified collection
 :
 : @author Peter Stadler
 : @param $collName
 : @param $cacheKey
 : @param $useCache
 : @return document-node()*
 :)
declare function core:getOrCreateColl($collName as xs:string, $cacheKey as xs:string, $useCache as xs:boolean) as document-node()* {
    let $lease := function($dateTimeOfCache) as xs:boolean {
        config:eXistDbWasUpdatedAfterwards($dateTimeOfCache) and $useCache
    }
    let $onFailure := function($errCode as item(), $errDesc as item()?) {
        core:logToFile('error', concat($errCode, ': ', $errDesc))
    }
    let $callBack := function() {
        if($collName eq 'diaries' and not($cacheKey = ('indices', 'A002068'))) then () (: Suppress the creation of diary collections for others than Weber :)
        else
            let $newColl := core:createColl($collName,$cacheKey)
            let $newIndex := 
                if($cacheKey eq 'indices') then wdt:lookup($collName, $newColl)('init-sortIndex')()
                else ()
            let $sortedColl := wdt:lookup($collName, $newColl)('sort')( map { 'personID' : $cacheKey} )
            (:let $log := core:logToFile('debug', 'Creating collection' || $collName || ': ' || $cacheKey):)
            return $sortedColl
    }
    return
        (: Do not cache all collections. This will result in too much memory consumption :)
        if($cacheKey = ('indices', 'A002068', 'A130001', 'A130002', 'A000213', 'A130003', 'A000914', 'A020040', 'A130004', 'A130005', 'A130006', 'A001002', 'A002078', 'A020043', 'A002160', 'A002085')) then mycache:collection($collName || $cacheKey, $callBack, $lease, $onFailure)
        else $callBack()
};

(:~
 : helper function for core:getOrCreateColl
 :
 : @author Peter Stadler
 : @param $collName
 : @param $cacheKey
 : @return document-node()*
 :)
declare %private function core:createColl($collName as xs:string, $cacheKey as xs:string) as document-node()* {
    if($cacheKey eq 'indices') then wdt:lookup($collName, ())('init-collection')()
    else if($collName eq 'backlinks') then wdt:backlinks(())('filter-by-person')($cacheKey)
    else wdt:lookup($collName, core:getOrCreateColl($collName, 'indices', true()))('filter-by-person')($cacheKey)
};

(:~
 : Return the undated documents of a given document type
 :
 : @author Peter Stadler 
 : @param $docType the document type (e.g., letters, writings)
 : @return document-node()*
 :)
declare function core:undated($docType as xs:string) as document-node()* {
    let $norm-file := norm:get-norm-doc($docType)
    for $i in $norm-file//norm:entry[not(text())]
    return core:doc($i/@docID)
};

(:~
 : Write log message to log file
 :
 : @author Peter Stadler
 : @param $priority to be used by util:log-app:  'error', 'warn', 'debug', 'info', 'trace'
 : @param $message to write
 : @return 
:)
declare function core:logToFile($priority as xs:string, $message as xs:string) as empty-sequence() {
    let $file := config:get-option('errorLogFile')
    let $message := concat($message, ' (rev. ', config:getCurrentSvnRev(), ')')
    return (
        util:log-app($priority, $file, $message),
        if($config:isDevelopment and ($priority = ('error', 'warn', 'debug'))) then util:log-system-out($message)
        else ()
    )
};

(:~
 : Creates a permalink by concatenating the $permaLinkPrefix (set in options) with the given path piped through config:link-to-current-app()
 : Mainly used for creating persistent links to documents by simply passing the docID  
 :
 : @author Peter Stadler
 : @param $relLink a relative path within the current app
 : @return xs:anyURI
 :)
declare function core:permalink($relLink as xs:string) as xs:anyURI? {
    xs:anyURI(config:get-option('permaLinkPrefix') || config:link-to-current-app($relLink))
};
