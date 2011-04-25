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

define generic permanent-link (obj :: <object>) => (url :: <url>);



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

define generic find-changes
    (storage :: <storage>, type :: subclass(<wiki-object>), #key start, count, #all-keys)
 => (changes :: <sequence>);

define generic store
    (storage :: <storage>, obj :: <wiki-object>, author :: <wiki-user>,
     comment :: <string>, meta-data :: <string-table>)
 => (revision :: <string>);

define generic delete
    (storage :: <storage>, obj :: <wiki-object>, author :: <wiki-user>,
     comment :: <string>, meta-data :: <string-table>)
 => ();

define generic rename
    (storage :: <storage>, obj :: <wiki-object>, new-name :: <string>,
     author :: <wiki-user>, comment :: <string>, meta-data :: <string-table>)
 => (revision :: <string>);

/// This is what the above methods should signal if they can't fullfill
/// their contract.
define class <storage-error> (<format-string-condition>, <serious-condition>)
end;



//// Changes

define class <wiki-change> (<object>)
  constant slot change-revision    :: <string>, required-init-keyword: revision:;
  constant slot change-author      :: <string>, required-init-keyword: author:;
  constant slot change-date        :: <date>,   required-init-keyword: date:;
  constant slot change-comment     :: <string>, required-init-keyword: comment:;

  // Keys that always exist: "name", "type", "action".
  // TODO: Be resilient to by-hand edits, in which case these items may not have
  //       been stored in the Notes for the commit.  This info could be recovered
  //       by grovelling over the output of "git whatchanged".
  constant slot change-meta-data   :: <string-table>, required-init-keyword: meta-data:;
end;

define function change-object-name
    (change :: <wiki-change>) => (name :: <string>)
  change.change-meta-data["name"]
end;

define function change-type-name
    (change :: <wiki-change>) => (name :: <string>)
  change.change-meta-data["type"]
end;

define function change-object-type
    (change :: <wiki-change>) => (type :: subclass(<wiki-object>))
  select (change.change-type-name by \=)
    "page" => <wiki-page>;
    "user" => <wiki-user>;
    "group" => <wiki-group>;
  end
end;

define function change-action
    (change :: <wiki-change>) => (action :: <string>)
  element(change.change-meta-data, "action", default: "change")
end;

define function standard-meta-data
    (object :: <wiki-object>, action :: <string>)
 => (meta-data :: <string-table>)
  let meta-data = make(<string-table>);
  meta-data["action"] := action;
  meta-data["name"] := select (object.object-class)
                         <wiki-page> => object.page-title;
                         <wiki-user> => object.user-name;
                         <wiki-group> => object.group-name;
                       end;
  meta-data["type"] := select (object.object-class)
                         <wiki-page> => "page";
                         <wiki-user> => "user";
                         <wiki-group> => "group";
                       end;
  meta-data
end;

define method permanent-link
    (change :: <wiki-change>) => (url :: <url>)
  let location = wiki-url("/page/diff/%s/%s",
                          change.change-object-name,
                          change.change-revision);
  transform-uris(request-url(current-request()), location, as: <url>)
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
  let changes = sort(find-recent-changes(),
                     test: method (change1, change2)
                             change1.change-date > change2.change-date   
                           end);
  let page-number = get-query-value("page", as: <integer>) | 1;
  let paginator = make(<paginator>,
                       sequence: changes,
                       current-page-number: page-number);
  set-attribute(page-context(), "recent-changes", paginator);
  next-method();
end;

/// Synopsis: Find changes for wiki objects of type 'for-type'.
///
/// Arguments:
///   for-type  - Should be <wiki-page>, <wiki-user>, or <wiki-group>
///               or <wiki-object> (the default).  <wiki-object> will
///               find changes for any object.
///   start     - A revision number at which to start searching (backward)
///               for changes.  With the git back-end this is a hash.
///               The default (#f) means to start with the most recent change.
///   name      - Only find changes for objects matching this name exactly.
///               For pages this matches the title.  The default (#f) matches
///               anything.
/// Values:
///   changes - a sequence of <wiki-change> objects representing object
///             creations, edits, deletions, or renames.
//
define method find-recent-changes
    (#key for-type :: subclass(<wiki-object>) = <wiki-object>,
          start :: false-or(<string>),
          name :: false-or(<string>))
 => (changes :: <sequence>)
  find-changes(*storage*, for-type, start: start, name: name)
end;

define body tag list-recent-changes in wiki
    (page :: <wiki-dsp>, do-body :: <function>)
    ()
  let pc = page-context();
  let previous-change = #f;
  let paginator :: <paginator> = get-attribute(pc, "recent-changes");
  for (change :: <wiki-change> in paginator)
    set-attribute(pc, "day", standard-date(change.change-date));
    set-attribute(pc, "previous-day",
                  previous-change & standard-date(previous-change.change-date));
    set-attribute(pc, "time", standard-time(change.change-date));
    set-attribute(pc, "permalink", as(<string>, permanent-link(change)));
    set-attribute(pc, "change-class", change.change-type-name);
    set-attribute(pc, "title", change.change-object-name);
    set-attribute(pc, "action", as(<string>, change.change-action));
    set-attribute(pc, "comment", change.change-comment);
    set-attribute(pc, "version", change.change-revision);
    set-attribute(pc, "verb", 
                  element($past-tense-table, change.change-action, default: #f)
                  | as(<string>, change.change-action));
    set-attribute(pc, "author", change.change-author);
    do-body();
    previous-change := change;
  end;
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



