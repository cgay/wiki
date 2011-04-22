Module: %wiki

define constant $wiki-version :: <string> = "2011.04.07"; // YYYY.mm.dd


// If you need to hold more than one of these locks, acquire them in
// this order: $group-lock, $user-lock, $page-lock.

/// All users are loaded from storage at startup and stored in this collection.
/// Users created after startup are added.  Keys are lowercased.
///
define variable *users* :: <string-table> = make(<string-table>);

/// Hold this when modifying *users*.
define constant $user-lock :: <lock> = make(<lock>);

define function find-user
    (name :: <string>, #key default)
  element(*users*, as-lowercase(name), default: default)
end;


/// All groups are loaded from storage at startup and stored in this collection.
/// Groups created after startup are added.  Keys are lowercased.
///
define variable *groups* :: <string-table> = make(<string-table>);

/// Hold this when modifying *groups*.
define constant $group-lock :: <lock> = make(<lock>);


/// Pages are stored here as they are lazily loaded.  find-page first
/// looks here and if not found, loads the page and stores it here.
/// Keys are page titles (not encoded, not lowercased) and values are
/// <wiki-page>s.
///
define variable *pages* :: <string-table> = make(<string-table>);

/// Hold this when modifying *pages*.
define constant $page-lock :: <lock> = make(<lock>);



/// All objects store in the wiki (pages, users, groups)
/// must subclass this.
///
define class <wiki-object> (<object>)
  constant slot creation-date :: <date> = current-date();
  // TODO:
  //constant slot modification-date :: <date> = <same as creation-date>;
end;

// Prefix for all wiki URLs.  Set to "" for no prefix.
define variable *wiki-url-prefix* :: <string> = "/wiki";

define tag base in wiki
    (page :: <wiki-dsp>) ()
  output("%s", *wiki-url-prefix*);
end;

define tag current in wiki
    (page :: <wiki-dsp>) ()
  output("%s", build-uri(request-url(current-request())));
end;

define function wiki-url
    (format-string, #rest format-args)
 => (url :: <url>)
  parse-url(concatenate(*wiki-url-prefix*,
                        apply(format-to-string, format-string, format-args)))
end;  

define constant $activate = #"activate";
define constant $create = #"create";
define constant $edit   = #"edit";
define constant $remove = #"remove";
define constant $rename = #"rename";
define constant $remove-group-owner = #"remove-group-owner";
define constant $remove-group-member = #"remove-group-member";

define table $past-tense-table = {
    $activate => "activated",
    $create => "created",
    $edit   => "edited",
    $remove => "removed",
    $rename => "renamed",
    $remove-group-owner => "removed as group owner",
    $remove-group-member => "removed as group member"
  };

define wf/error-test (exists) in wiki end;




//// Storage protocol

/// Any back-end storage mechanism must be a subclass of this and support
/// the generics that specialize on it.
define class <storage> (<object>)
end;

/// This is initialized when the config file is loaded.
define variable *storage* :: false-or(<storage>) = #f;


/// Initialize storage upon startup
define generic initialize-storage-for-reads
    (storage :: <storage>) => ();

define generic initialize-storage-for-writes
    (storage :: <storage>, admin-user :: <wiki-user>) => ();


define generic load
    (storage :: <storage>, class :: subclass(<wiki-object>), name :: <string>,
     #key)
 => (obj :: <wiki-object>);

define generic load-all
    (storage :: <storage>, class :: subclass(<wiki-object>))
 => (objects :: <sequence>);

define generic find-or-load-pages-with-tags
    (storage :: <storage>, tags :: <sequence>) => (pages :: <sequence>);

define generic store
    (storage :: <storage>, obj :: <wiki-object>, author :: <wiki-user>,
     comment :: <string>, meta-data :: <string>)
 => (revision :: <string>);

define generic delete
    (storage :: <storage>, obj :: <wiki-object>, author :: <wiki-user>,
     comment :: <string>)
 => ();

define generic rename
    (storage :: <storage>, obj :: <wiki-object>, new-name :: <string>,
     author :: <wiki-user>, comment :: <string>)
 => (revision :: <string>);

/// This is what the above methods should signal if they can't fullfill
/// their contract.
define class <storage-error> (<format-string-condition>, <serious-condition>)
end;




// Standard date format.  The plan is to make this customizable per user
// and to use the user's timezone.  For now just ISO 8601...
//
define method standard-date-and-time
    (date :: <date>) => (date-and-time :: <string>)
  as-iso8601-string(date)
end;

define method standard-date
    (date :: <date>) => (date :: <string>)
  format-date("%Y.%m.%d", date)
end;

define method standard-time
    (date :: <date>) => (time :: <string>)
  format-date("%H:%M", date)
end;

define tag show-version-published in wiki
    (page :: <wiki-dsp>)
    (formatted :: <string>)
  output("%s", format-date(formatted, *page*.creation-date));
end;

define tag show-page-published in wiki
    (page :: <wiki-dsp>)
    (formatted :: <string>)
  if (*page*)
    output("%s", format-date(formatted, *page*.creation-date));
  end if;
end;

// Rename to show-revision
define tag show-version-number in wiki
    (page :: <wiki-dsp>)
    ()
  output("%s", *page*.page-revision);
end; 

// Rename to show-comment
define tag show-version-comment in wiki
    (page :: <wiki-dsp>)
    ()
  output("%s", *page*.page-comment);
end;


//// Recent Changes

define class <recent-changes-page> (<wiki-dsp>)
end;

define method respond-to-get
    (page :: <recent-changes-page>, #key)
  let changes = sort(wiki-changes(),
                     test: method (change1, change2)
                             change1.creation-date > change2.creation-date   
                           end);
  let page-number = get-query-value("page", as: <integer>) | 1;
  let paginator = make(<paginator>,
                       sequence: changes,
                       current-page-number: page-number);
  set-attribute(page-context(), "recent-changes", paginator);
  next-method();
end;

// Return a sequence of changes of the given type.  This is used for
// Atom feed requests, in which case there is (presumably) no authenticated
// user so it only returns changes for publicly viewable pages in that case.
//
define method wiki-changes
    (#key change-type :: false-or(<class>),
          tag :: false-or(<string>),
          name :: false-or(<string>))
 => (changes :: <sequence>)
  TODO--wiki-changes;
end method wiki-changes;

define body tag list-recent-changes in wiki
    (page :: <wiki-dsp>, do-body :: <function>)
    ()
  TODO--list-recent-changes;
/*
  let pc = page-context();
  let previous-change = #f;
  let paginator :: <paginator> = get-attribute(pc, "recent-changes");
  for (change in paginator)
    set-attribute(pc, "day", standard-date(change.creation-date));
    set-attribute(pc, "previous-day",
                  previous-change & standard-date(previous-change.creation-date));
    set-attribute(pc, "time", standard-time(change.creation-date));
    set-attribute(pc, "permalink", as(<string>, permanent-link(change)));
    set-attribute(pc, "change-class", change.change-type-name);
    set-attribute(pc, "title", change.title);
    set-attribute(pc, "action", as(<string>, change.change-action));
    set-attribute(pc, "comment", change.comments[0].content.content);
    set-attribute(pc, "version",
                  instance?(change, <wiki-page-change>) & change.change-version);
    set-attribute(pc, "verb", 
                  element($past-tense-table, change.change-action, default: #f)
                  | as(<string>, change.change-action));
    set-attribute(pc, "author",
                  begin
                    let authors = change.authors;
                    let user = ~empty?(authors) & find-user(authors[0]);
                    user & user.user-name
                  end);
*/
    do-body();
/*
    previous-change := change;
  end;
*/
end tag list-recent-changes;

define tag base-url in wiki
    (page :: <wiki-dsp>)
    ()
  let url = current-request().request-absolute-url; // this may make a new url
  output("%s", build-uri(make(<url>,
                              scheme: url.uri-scheme,
                              host: url.uri-host,
                              port: url.uri-port)));
end tag base-url;

define sideways method permission-error (action, #key)
//  respond-to(#"get", *not-logged-in-page*);  
end;

define variable *not-logged-in-page* = #f;

define sideways method authentication-error (action, #key)
  respond-to-get(*not-logged-in-page*);
end;



