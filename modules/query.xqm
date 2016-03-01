xquery version "3.1" encoding "UTF-8";

(:~
 : Functions for querying data from the WeGA-data app 
:)
module namespace query="http://xquery.weber-gesamtausgabe.de/modules/query";
declare default collation "?lang=de;strength=primary";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace mei="http://www.music-encoding.org/ns/mei";

import module namespace config="http://xquery.weber-gesamtausgabe.de/modules/config" at "config.xqm";
import module namespace norm="http://xquery.weber-gesamtausgabe.de/modules/norm" at "norm.xqm";
import module namespace core="http://xquery.weber-gesamtausgabe.de/modules/core" at "core.xqm";
import module namespace str="http://xquery.weber-gesamtausgabe.de/modules/str" at "str.xqm";
import module namespace date="http://xquery.weber-gesamtausgabe.de/modules/date" at "date.xqm";
import module namespace functx="http://www.functx.com";

(:~
 : Print the regularised name for a given person or place ID
 :
 : @author Peter Stadler
 : @return xs:string
 :)
declare function query:get-reg-name($key as xs:string) as xs:string {
    (:
    Leider zu langsam
    
    let $regName := collection('/db/persons')//id($key)/tei:persName[@type='reg']
    return wega:cleanString($regName)
    :)
    let $dictionary := norm:get-norm-doc(config:get-doctype-by-id($key)) 
    let $response := $dictionary//@docID[. = $key]
    return 
        if(exists($response)) then $response/parent::norm:entry/text()
        else ''
};

(:~
 : Print the regularised title for a given doc ID (works, writings, etc.)
 :
 : @author Peter Stadler
 : @return xs:string
 :)
declare function query:get-reg-title($docID as xs:string) as xs:string {
    let $dictionary := norm:get-norm-doc(config:get-doctype-by-id($docID)) 
    let $response := $dictionary//@docID[. = $docID]
    return 
        if(exists($response)) then $response/parent::norm:entry/text()
        else ''
};

(:~
 : Grabs the first author from a TEI document and returns its WeGA ID
 :
 : @author Peter Stadler 
 : @param $item the id of the TEI document (or the document node itself) to grab the author from
 : @return xs:string the WeGA ID
:)
declare function query:get-authorID($doc as document-node()?) as xs:string {
    let $author-element := query:get-author-element($doc)[1]
    return
        if(exists($doc)) then 
            if(config:is-diary($doc/tei:ab/@xml:id)) then 'A002068' (: Diverse Sonderbehandlungen fürs Tagebuch :)
            else if($author-element/@key) then $author-element/@key/string()
            else if($author-element/@dbkey) then $author-element/@dbkey/string()
            else config:get-option('anonymusID')
        else ''
};

(:~
 : Grabs the first author from a TEI document and returns its name (as noted in the document)
 : For the regularized name see query:get-reg-name()
 :
 : @author Peter Stadler 
 : @param $item the id of the TEI document (or the document node itself) to grab the author from
 : @return xs:string the name of the author
:)
declare function query:get-authorName($doc as document-node()?) as xs:string {
    if(exists($doc)) then 
        if(config:is-diary($doc/tei:ab/@xml:id)) then 'Carl Maria von Weber' (: Diverse Sonderbehandlungen fürs Tagebuch :)
        else normalize-space(query:get-author-element($doc)[1])
    else ''
};

declare function query:get-author-element($doc as document-node()?) as element()* {
    if(exists($doc//mei:titleStmt/mei:respStmt/mei:persName[@role = 'cmp'])) then $doc//mei:titleStmt/mei:respStmt/mei:persName[@role = 'cmp']
    else if(exists($doc//tei:fileDesc/tei:titleStmt/tei:author)) then $doc//tei:fileDesc/tei:titleStmt/tei:author
    else ()
};

(:~
 : Retrieves the WeGA person ID by PND
 :
 : @author Peter Stadler
 : @param $pnd the PND number
 : @return xs:string
:)
declare function query:getIDByPND($pnd as xs:string) as xs:string {
    core:data-collection('persons')//tei:idno[.=$pnd][@type='gnd']/parent::tei:person/string(@xml:id)
};

(:~
 : Return GND 
 :
 : @author Peter Stadler
 : @param $item may be xs:string (the WeGA ID), document-node() (of a person file), or a tei:person element
 : @return the GND as xs:string, empty string or empty sequence if nothing was found 
:)
declare function query:get-gnd($item as item()) as xs:string? {
    typeswitch($item)
        case xs:string return core:doc($item)//tei:idno[@type = 'gnd']/string()
        case document-node() return $item//tei:idno[@type = 'gnd']/string()
        case element(tei:person) return $item/tei:idno[@type = 'gnd']/string()
        default return ()
};

(:~ 
 : Gets events of the day for a certain date
 :
 : @author Peter Stadler
 : @param $date todays date
 : @return tei:date* tei:date elements that match given day and month of $date
 :)
declare function query:getTodaysEvents($date as xs:date) as element(tei:date)* {
    let $day := functx:pad-integer-to-length(day-from-date($date), 2)
    let $month := functx:pad-integer-to-length(month-from-date($date), 2)
    let $date-regex := concat('^', string-join(('\d{4}',$month,$day),'-'), '$')
    return 
        collection(config:get-option('letters'))//tei:dateSender/tei:date[matches(@when, $date-regex)] union
        collection(config:get-option('persons'))//tei:date[matches(@when, $date-regex)][not(preceding-sibling::tei:date[matches(@when, $date-regex)])][parent::tei:birth or parent::tei:death][ancestor::tei:person/@source='WeGA']
};

(:~
 : Gets reg title
 :
 : @author Peter Stadler
 : @param $doc the TEI document
 : @return xs:string
 :)
declare function query:get-title-element($doc as document-node(), $lang as xs:string) as element()* {
    let $docID := $doc/*/@xml:id
    return
        if(config:is-diary($docID)) then <tei:date>{$doc/tei:ab/data(@n)}</tei:date>
        else if(config:is-work($docID)) then $doc//mei:fileDesc/mei:titleStmt/mei:title[not(@type)]
        else if(config:is-var($docID)) then $doc//tei:fileDesc/tei:titleStmt/tei:title[@level = 'a'][@xml:lang = $lang]
        else $doc//tei:fileDesc/tei:titleStmt/tei:title[@level = 'a']
};

declare function query:get-main-source($doc as document-node()) as element()? {
    if($doc//tei:sourceDesc) then (: for writings and letters :)
        if($doc//tei:sourceDesc/tei:listWit) then $doc//tei:sourceDesc/tei:listWit/tei:witness[@n='1']/*
        else $doc//tei:sourceDesc/*
    else if($doc//mei:sourceDesc) then () (: for works :)
    else if($doc/tei:biblStruct) then $doc/tei:biblStruct (: for biblio :)
    else ()
};

(:~
 : Get the normalized date for a document
 : (needed for core:sortColl() as well as norm:get-norm-doc())
 :
 : @author Peter Stadler
 : @param $doc the TEI document
 : @return xs:date
 :)
declare function query:get-normalized-date($doc as document-node()) as xs:date? {
    let $docID := $doc/*/@xml:id
    let $date := 
        switch(config:get-doctype-by-id($docID))
        case 'writings' return date:getOneNormalizedDate(query:get-main-source($doc)/tei:monogr/tei:imprint/tei:date, false())
        case 'letters' return date:getOneNormalizedDate(($doc//tei:dateSender/tei:date, $doc//tei:dateAddressee/tei:date)[1], false())
        case 'biblio' return date:getOneNormalizedDate($doc//tei:imprint/tei:date, false())
        case 'diaries' return $doc/tei:ab/data(@n)
        case 'news' return $doc//tei:date[parent::tei:publicationStmt]/substring(@when,1,10)
        default return () 
    return 
        if($date castable as xs:date) then $date cast as xs:date
        else ()
};

(:~
 : see also $search:valid-params
~:)
declare function query:get-facets($collection as node()*, $facet as xs:string) as item()* {
    switch($facet)
    case 'sender' return $collection//@key[ancestor::tei:sender]
    case 'addressee' return $collection//@key[ancestor::tei:addressee]
    case 'docStatus' return $collection/*/@status | $collection//tei:revisionDesc/@status
    case 'placeOfSender' return $collection//tei:placeName[parent::tei:placeSender]
    case 'placeOfAddressee' return $collection//tei:placeName[parent::tei:placeAddressee]
    case 'journals' return $collection//tei:title[@level='j'][not(@type='sub')][ancestor::tei:sourceDesc]
    case 'places' return $collection//tei:settlement[ancestor::tei:text or ancestor::tei:ab]
    case 'dedicatees' return $collection//mei:persName[@role='dte']/@dbkey
    case 'lyricists' return $collection//mei:persName[@role='lyr']/@dbkey
    case 'librettists' return $collection//mei:persName[@role='lbt']/@dbkey
    case 'composers' return $collection//mei:persName[@role='cmp']/@dbkey
    case 'docSource' return $collection/tei:person/@source
    case 'occupations' return $collection//tei:occupation
    case 'residences' return $collection//tei:settlement[parent::tei:residence]
        (: index-keys does not work with multiple whitespace separated keys
            probably need to change to ft:query() someday?!
        :)
    case 'persons' return ($collection//tei:persName[ancestor::tei:text or ancestor::tei:ab]/@key | $collection//tei:rs[@type='person'][ancestor::tei:text or ancestor::tei:ab]/@key)
    case 'works' return ($collection//tei:workName/@key[not(contains(., ' '))] | $collection//tei:rs[@type='work']/@key[not(contains(., ' '))])
    case 'authors' return $collection//tei:author/@key
    case 'editors' return $collection//tei:editor/@key
    case 'biblioType' return $collection/tei:biblStruct/@type
    case 'docTypeSubClass' return $collection//tei:text/@type
    default return ()
};

declare function query:correspondence-partners($id as xs:string) as map(*) {
    map:new(
        for $i in (norm:get-norm-doc('letters')//@addresseeID[contains(., $id)]/parent::norm:entry | norm:get-norm-doc('letters')//@authorID[contains(., $id)]/parent::norm:entry)/(@authorID, @addresseeID)/tokenize(., '\s+') 
        group by $partnerID := data($i)
        return
            map:entry($partnerID, count($i))
    )
};

(:~
 : Lookup the places of a diary entry
 :
 : @param $diaryDay the document with the diary entry 
 : @return an array of strings with the canonical names of the places 
~:)
declare function query:place-of-diary-day($diaryDay as document-node()) as array(xs:string) {
    let $placeIDs := tokenize($diaryDay/tei:ab/@where, '\s+')[config:is-place(.)]
    return
        array {
            $placeIDs ! query:get-reg-name(.)
        }
};

(:~
 : Extract all contributors from the document
~:)
declare function query:contributors($doc as document-node()?) as xs:string* {
    let $contributors := 
        $doc//tei:fileDesc/tei:titleStmt/(tei:author | tei:editor) |
        $doc//tei:respStmt/tei:name |
        $doc//mei:respStmt/mei:persName
    return
        $contributors ! data(.)
};
