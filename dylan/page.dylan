Module: %wiki


/// Default number of pages to show on the list-pages page.
define constant $default-page-count :: <integer> = 25;


// Represents a user-editable wiki page revision.  Not to be confused
// with <wiki-dsp>, which is a DSP maintained in our source code tree.
//
define class <wiki-page> (<wiki-object>)

  slot page-title :: <string>,
    required-init-keyword: title:;

  slot page-content :: <string>,
    required-init-keyword: content:;

  // Comment entered by the user describing the changes for this revision.
  slot page-comment :: <string>,
    required-init-keyword: comment:;

  // The owner has special rights over the page, depending on the ACLs.
  // The owner only changes if explicitly changed via the edit-acls page.
  // TODO: move this into <acls>.
  slot page-owner :: <wiki-user>,
    required-init-keyword: owner:;

  // The author is the one who saved this particular revision of the page.
  slot page-author :: <wiki-user>,
    required-init-keyword: author:;

  // Tags (strings) entered by the author when the page was saved.
  slot page-tags :: <sequence>,
    required-init-keyword: tags:;

  slot page-access-controls :: <acls>,
    required-init-keyword: access-controls:;

  // e.g. a git commit hash or a revision number
  // Filled in by the storage back-end.
  slot page-revision :: <string>,
    init-keyword: revision:;

end class <wiki-page>;


define thread variable *page* :: false-or(<wiki-page>) = #f;

define named-method page? in wiki
    (page :: <dylan-server-page>)
  *page* ~= #f
end;


//// URLs

define method permanent-link
    (page :: <wiki-page>, #key escaped?, full?)
 => (url :: <url>)
  page-permanent-link(page.page-title)
end;

define method page-permanent-link
    (title :: <string>)
 => (url :: <url>)
  let location = wiki-url("/page/view/%s", title);
  transform-uris(request-url(current-request()), location, as: <url>)
end;

define method redirect-to (page :: <wiki-page>)
  redirect-to(permanent-link(page));
end;


define method find-page
    (title :: <string>)
 => (page :: false-or(<wiki-page>))
  element(*pages*, title, default: #f)
end;

// In fact we load all pages at startup for now (to simplify searches
// and iteration over lists of pages) so this probably never loads anything.
//
define method find-or-load-page
    (title :: <string>)
  find-page(title)
  | block ()
      // Load page is slow, do it without the lock held.
      let loaded-page = load(*storage*, <wiki-page>, title);
      with-lock ($page-lock)
        // check again with lock held
        find-page(title)
        | (*pages*[title] := loaded-page)
      end
    exception (ex :: <git-storage-error>)
      // ignored
    end;
end method find-or-load-page;

// The plan is for this to eventually support many more search criteria,
// such as searching by owner, author, date ranges, etc.
//
define method find-pages
    (#key tags :: <sequence> = #[],
          order-by :: <function> = title-less?)
 => (pages :: <sequence>)
  let pages = sort(with-lock ($page-lock)
                     value-sequence(*pages*)
                   end,
                   test: order-by);
  if (~empty?(tags))
    local method page-has-tags? (page :: <wiki-page>)
            any?(method (tag)
                   member?(tag, page.page-tags, test: \=)
                 end,
                 tags)
          end;
    pages := choose(page-has-tags?, pages);
  end;
  pages
end;

define function title-less?
    (p1 :: <wiki-page>, p2 :: <wiki-page>) => (less? :: <boolean>)
  p1.page-title < p2.page-title
end;

define function creation-date-newer?
    (p1 :: <wiki-page>, p2 :: <wiki-page>) => (less? :: <boolean>)
  p1.creation-date > p2.creation-date
end;


// todo -- Implement this as a wiki page.
define constant $reserved-tags :: <sequence> = #["news"];

define method reserved-tag?
    (tag :: <string>) => (reserved? :: <boolean>)
  member?(tag, $reserved-tags, test: \=)
end;

define method save-page
    (title :: <string>, content :: <string>, comment :: <string>, tags :: <sequence>)
 => (page :: <wiki-page>)
  let user = authenticated-user();
  let page = make(<wiki-page>,
                  title: title,
                  content: content,
                  tags: tags | #(),
                  comment: comment,
                  author: user,
                  owner: user,
                  access-controls: $default-access-controls);
  with-lock ($page-lock)
    *pages*[title] := page;
  end;
  page.page-revision := store(*storage*, page, page.page-author, comment);
/*
  TODO: 
  block ()
    generate-connections-graph(page);
  exception (ex :: <serious-condition>)
    // we don't care about the graph (yet?)
    // maybe the server doesn't have "dot" installed.
    log-error("Error generating connections graph for page %s: %s",
              title, ex);
  end;
*/
  page
end method save-page;

/* Not converted to new git-backed wiki yet...
define method generate-connections-graph
    (page :: <wiki-page>) => ()
  let graph = make(gvr/<graph>);
  let node = gvr/create-node(graph, label: page.page-title);
  let backlinks = find-backlinks(page);
  backlinks := map(page-title, backlinks);
  gvr/add-predecessors(node, backlinks);
  gvr/add-successors(node, last(page.page-versions).references);
  for (node in gvr/nodes(graph))
    node.gvr/attributes["URL"] := build-uri(page-permanent-link(node.gvr/label));
    node.gvr/attributes["color"] := "blue";
    node.gvr/attributes["style"] := "filled";
    node.gvr/attributes["fontname"] := "Verdana"; 
    node.gvr/attributes["shape"] := "note";
  end for;
  let temporary-graph = gvr/generate-graph(graph, node, format: "svg");
  let graph-file = as(<file-locator>, temporary-graph);
  if (file-exists?(graph-file))
    let destination = as(<file-locator>,
                         concatenate("graphs/", page.page-title, ".svg"));
    rename-file(graph-file, destination, if-exists: #"replace");
  end if;
end;
*/

/*
define method extract-references
    (version :: <wiki-page-version>)
 => (references :: <sequence>)
  let references = list();
  let content = version.content.content;
  let regex = compile-regex("\\[\\[([^\\]]*)\\]\\]");
  let start = 0;
  while (regex-position(regex, content, start: start))
    let (#rest matches) = regex-search-strings(regex, slice(content, start, #f));
    if (first(matches))
      references := add!(references, second(matches));
    end if;
    let (#rest positions) = regex-position(regex, content, start: start);
    start := last(positions) | size(content);
  end while;
  references;
end;
*/

define method rename-page
    (page :: <wiki-page>, new-title :: <string>,
     #key comment :: false-or(<string>))
 => ()
  let author = authenticated-user();
  let old-title = page.page-title;
  rename(*storage*, page, new-title, author,
         comment | format-to-string("Renamed from %= to %=", old-title, new-title));
  with-lock ($page-lock)
    remove-key!(*pages*, old-title);
    *pages*[new-title] := page;
  end;
end method rename-page;


define generic find-backlinks
    (object :: <object>)
 => (backlinks :: <stretchy-vector>); 

define method find-backlinks
    (page :: <wiki-page>)
 => (backlinks :: <stretchy-vector>);
  find-backlinks(page.page-title);
end;

define method find-backlinks
    (title :: <string>)
 => (backlinks :: <stretchy-vector>)
  let backlinks = make(<stretchy-vector>);
  TODO--maintain-page-backlink-info;
  backlinks
end;

define method discussion-page?
    (page :: <wiki-page>)
 => (is? :: <boolean>)
  let (matched?, discussion, title)
    = regex-search-strings(compile-regex("(Discussion: )(.*)"),
                           page.page-title);
  matched? = #t;
end;

define function redirect-content?
    (content :: <string>)
 => (content :: false-or(<string>), 
     title :: false-or(<string>))
  let (content, title) = 
    regex-search-strings(compile-regex("^#REDIRECT \\[\\[(.*)\\]\\]"),
                         content);
  values(content, title);
end;



//// List Versions

define class <page-versions-page> (<wiki-dsp>)
end;

define method respond-to-get
    (page :: <page-versions-page>, #key title :: <string>)
  let wiki-page = find-or-load-page(percent-decode(title));
  if (wiki-page)
    set-attribute(page-context(), "title", percent-decode(title));
    set-attribute(page-context(), "page-versions", TODO--page-versions);
    next-method()
  else
    respond-to-get(*non-existing-page-page*, title: title);
  end;
end;

define body tag list-page-versions in wiki
    (page :: <wiki-dsp>, do-body :: <function>)
    ()
  let pc = page-context();
  for (page in get-attribute(pc, "page-versions"))
    set-attribute(pc, "author", page.page-author.user-name);
    // todo -- make date format and TZ a user setting.
    set-attribute(pc, "published",
                  format-date("%e %b %Y %H:%M:%S", page.creation-date));
    set-attribute(pc, "comment", iff(page.page-comment.empty?,
                                     "-",
                                     page.page-comment));
    set-attribute(pc, "version-number", page.page-revision);
    do-body();
  end;
end tag list-page-versions;


//// Page connections (backlinks)

define class <connections-page> (<wiki-dsp>)
end;

define method respond-to-get
    (page :: <connections-page>, #key title :: <string>)
  let title = percent-decode(title);
  dynamic-bind (*page* = find-or-load-page(title))
    if (*page*)
      next-method();
    else
      respond-to-get(*non-existing-page-page*, title: title);
    end;
  end;
end method respond-to-get;

define body tag list-page-backlinks in wiki
    (page :: <wiki-dsp>, do-body :: <function>)
    ()
  let backlinks = find-backlinks(*page*);
  if (empty?(backlinks))
    output("There are no connections to this page.");
  else
    for (backlink in backlinks)
      set-attribute(page-context(), "backlink", backlink.page-title);
      set-attribute(page-context(), "backlink-url", permanent-link(backlink));
      do-body();
    end for;
  end if;
end;



//// List Pages

define class <list-pages-page> (<wiki-dsp>) end;

define method respond-to-get
    (dsp :: <list-pages-page>, #key)
  if (get-query-value("go"))
    redirect-to(page-permanent-link(get-query-value("query")));
  else
    let pc = page-context();
    local method page-info (page :: <wiki-page>)
            make-table(<string-table>,
                       "title" => page.page-title,
                       "when-published" => standard-date-and-time(page.creation-date),
                       "latest-authors" => page.page-author.user-name)
          end;
    let current-page = get-query-value("page", as: <integer>) | 1;
    let paginator = make(<paginator>,
                         sequence: map(page-info, find-pages()),
                         page-size: $default-page-count,
                         current-page-number: current-page);
    set-attribute(pc, "wiki-pages", paginator);
    next-method();
  end;
end method respond-to-get;


//// Remove page

define class <remove-page-page> (<wiki-dsp>)
end;

define method respond-to-get
    (dsp :: <remove-page-page>, #key title :: <string>)
  dynamic-bind (*page* = find-or-load-page(title))
    process-template(dsp);
  end;
end;

define method respond-to-post
    (dsp :: <remove-page-page>, #key title :: <string>)
  let page = find-or-load-page(percent-decode(title));
  if (page)
    delete(*storage*, page, authenticated-user(),
           get-query-value("comment")
           | format-to-string("Removed page %=", title));
    add-page-note("Page %= has been deleted.", title);
    redirect-to(wiki-url("/") /* generate-url("wiki.home") */);
  else
    respond-to-get(*non-existing-page-page*, title: title);
  end;
end;


// Provide backward compatibility with old wiki URLs
// /wiki/view.dsp?title=t&version=v
// 
define method show-page-back-compatible
    (#key)
  with-query-values (title, version)
    let title = percent-decode(title);
    let version = version & percent-decode(version);
    let default = current-request().request-absolute-url;
    let url = make(<url>,
                   scheme: default.uri-scheme,
                   host: default.uri-host,
                   port: default.uri-port,
                   // No, I don't understand the empty string either.
                   path: concatenate(list("", "pages", title),
                                     iff(version,
                                         list("versions", version),
                                         #())));
    let location = as(<string>, url);
    moved-permanently-redirect(location: location,
                               header-name: "Location",
                               header-value: location);
  end;
end;

define method show-page-responder
    (#key title :: <string>, version)
  let title = percent-decode(title);
  dynamic-bind (*page* = find-or-load-page(title))
    respond-to-get(case
                     *page* => *view-page-page*;
                     authenticated-user() => *edit-page-page*;
                     otherwise => *non-existing-page-page*;
                   end,
                   title: title);
  end;
end method show-page-responder;



//// Edit Page

define class <edit-page-page> (<wiki-dsp>)
end;

define method respond-to-get
    (page :: <edit-page-page>, #key title :: <string>)
  let title = percent-decode(title);
  let pc = page-context();
  if (authenticated-user())
    set-attribute(pc, "title", title);
    set-attribute(pc, "previewing?", #f);
    dynamic-bind (*page* = find-or-load-page(title))
      if (*page*)
        set-attribute(pc, "original-title", *page*.page-title);
        set-attribute(pc, "content", *page*.page-content);
        set-attribute(pc, "owner", *page*.page-owner);
        set-attribute(pc, "tags", unparse-tags(*page*.page-tags));
      end;
      next-method();
    end;
  else
    // This shouldn't happen unless the user typed in the /edit url,
    // since the edit option shouldn't be available unless logged in.
    add-page-error("You must be logged in to edit wiki pages.");
    respond-to-get(*view-page-page*, title: title);
  end;
end method respond-to-get;

// Note that when the title is changed and the page is being previewed
// we have to keep track of the old title.  The POST is always to the
// existing title, and when it's not a preview, the rename is done.
//
define method respond-to-post
    (wiki-dsp :: <edit-page-page>, #key title :: <string>)
  let title = percent-decode(title);
  let page = find-or-load-page(title);
  with-query-values (title as new-title, content, comment, tags, button)
    let tags = iff(tags, parse-tags(tags), #[]);
    let new-title = new-title & trim(new-title);
    let previewing? = (button = "Preview");

    // Handle page renaming.
    // TODO: potential race conditions here.  Should really lock the old and
    //       new pages around the find-page and rename-page. Low priority now.
    if (new-title & ~empty?(new-title) & new-title ~= title)
      if (find-or-load-page(new-title))
        add-field-error("title", "A page with this title already exists.");
      else
        if (page & ~previewing?)
          title := new-title;
          rename-page(page, new-title, comment: comment);
        end;
      end;
    end;

    let author = authenticated-user();
    if (page & ~has-permission?(author, page, $modify-content))
      add-page-error("You do not have permission to edit this page.");
    end;

    let reserved-tags = choose(reserved-tag?, tags);
    if (~empty?(reserved-tags) & ~administrator?(author))
      add-field-error("tags", "The tag%s %s %s reserved for administrator use.",
                      iff(reserved-tags.size = 1, "", "s"),
                      join(tags, ", ", conjunction: " and "),
                      iff(reserved-tags.size = 1, "is", "are"));
    end;

    if (previewing? | page-has-errors?())
      set-attribute(page-context(), "previewing?", #t);
      set-attribute(page-context(), "original-title", page.page-title);
      process-template(wiki-dsp);
    else
      let page = save-page(title, content | "", comment, tags);
      redirect-to(page);
    end;
  end;
end method respond-to-post;


//// View Diff

define class <view-diff-page> (<wiki-dsp>) end;

// /Title/diff/n  diffs versions n - 1 and n.
// /Title/diff/n/m diffs versions n and m.
// Note that in the first case n is the newer version and in the latter
// case n is the older version.
//
// TODO:
define method respond-to-get
    (page :: <view-diff-page>,
     #key title :: <string>,
          version1 :: <string>,
          version2 :: false-or(<string>))
  let title = percent-decode(title);
  dynamic-bind (*page* = find-page(title))  // only for <show-page-title/>
    if (*page*)
      block (return)
        let pc = page-context();
        let old-rev = #f;
        let new-rev = #f;
        if (~old-rev)
          add-page-error("%s revision #%s does not exist.", title, ix1 + 1);
        end;
        if (~new-rev)
          add-page-error("%s revision #%s does not exist.", title, ix2 + 1);
        end;
        if (old-rev & new-rev)

// Clearly we want to use "git diff" here.

          let seq1 = split(old-rev.page-content, '\n');
          let seq2 = split(new-rev.page-content, '\n');
          set-attribute(pc, "diffs", sequence-diff(seq1, seq2));
          // sequence-diff doesn't hang onto the actual lines, only indexes,
          // so store them too...
          set-attribute(pc, "seq1", seq1);
          set-attribute(pc, "seq2", seq2);
        end;
      exception (ex :: <error>)
        add-page-error("Invalid version number: %s", ex);
      end;
    else
      add-page-error("The page does not exist: %s", title);
    end;
    next-method();
  end;
end method respond-to-get;

define method print-diff-entry
    (entry :: <insert-entry>, seq1 :: <sequence>, seq2 :: <sequence>)
  let lineno1 = entry.source-index + 1;
  let lineno2 = entry.element-count + entry.source-index;
  if (lineno1 = lineno2)
    output("Added line %d:<br/>", lineno1);
  else
    output("Added lines %d - %d:<br/>", lineno1, lineno2);
  end;
  for (line in copy-sequence(seq2, start: lineno1 - 1, end: lineno2),
       lineno from lineno1)
    output("%d: %s<br/>", lineno, line);
  end;
end method print-diff-entry;
  
define method print-diff-entry
    (entry :: <delete-entry>, seq1 :: <sequence>, seq2 :: <sequence>)
  let lineno1 = entry.dest-index + 1;
  let lineno2 = entry.element-count + entry.dest-index;
  if (lineno1 = lineno2)
    output("Removed line %d:<br/>", lineno1);
  else
    output("Removed lines %d - %d:<br/>", lineno1, lineno2);
  end;
  for (line in copy-sequence(seq1, start: lineno1 - 1, end: lineno2),
       lineno from lineno1)
    output("%d: %s<br/>", lineno, line);
  end;
end method print-diff-entry;

define tag show-diff-entry in wiki
    (page :: <view-diff-page>)
    (name :: <string>)
  let pc = page-context();
  let entry = get-attribute(pc, name);
  let seq1 = get-attribute(pc, "seq1");
  let seq2 = get-attribute(pc, "seq2");
  print-diff-entry(entry, seq1, seq2);
end tag show-diff-entry;


define method redirect-to-page-or
    (page :: <wiki-dsp>, #key title :: <string>)
  let title = percent-decode(title);
  dynamic-bind (*page* = find-or-load-page(title))
    if (*page*)
      respond-to-get(page);
    else
      redirect-to(page-permanent-link(title));
    end if;
  end;
end method redirect-to-page-or;



//// Tags

define tag show-page-permanent-link in wiki
    (page :: <wiki-dsp>)
    ()
  if (*page*)
    output("%s", permanent-link(*page*))
  end;
end;

// Show the title of the main page corresponding to a discussion page.
define tag show-main-page-title in wiki
    (page :: <wiki-dsp>) ()
  if (*page*)
    let main-title = regex-replace(*page*.page-title, compile-regex("^Discussion: "), "");
    output("%s", escape-xml(main-title));
  end;
end tag show-main-page-title;

// Show the title of the discussion page corresponding to a main page.
define tag show-discussion-page-title in wiki
    (page :: <wiki-dsp>) ()
  if (*page*)
    let discuss-title = concatenate("Discussion: ", *page*.page-title);
    output("%s", escape-xml(discuss-title));
  end;
end tag show-discussion-page-title;

define tag show-page-title in wiki
    (page :: <wiki-dsp>)
    ()
  if (*page*)
    output("%s", escape-xml(*page*.page-title));
  end;
end;

define tag show-page-owner in wiki
    (page :: <wiki-dsp>)
    ()
  if (*page*)
    output("%s", escape-xml(*page*.page-owner.user-name))
  end;
end;

define tag show-page-content in wiki
    (page :: <wiki-dsp>)
    (content-format :: false-or(<string>))
  let raw-content = get-attribute(page-context(), "content")
                    | (*page* & *page*.page-content)
                    | get-query-value("content")
                    | "";
  case
    content-format = "xhtml"
      => output("%s", wiki-markup-to-html(raw-content)); // parse-wiki-markup(content);
    otherwise
      => output("%s", raw-content);
  end case;
end;

define tag show-version in wiki
    (page :: <wiki-dsp>)
    ()
  output("%s", *page*.page-revision);
end;


// body tags 

define body tag list-page-tags in wiki
    (page :: <wiki-dsp>, do-body :: <function>)
    ()
  if (*page*)
    // Is it correct to be using the tags from the newest page version?
    // At least this DSP tag should be called show-latest-page-tags ...
    for (tag in *page*.page-tags)
      dynamic-bind(*tag* = tag)
        do-body();
      end;
    end for;
  elseif (get-query-value("tags"))
    output("%s", escape-xml(get-query-value("tags")));
  end if;
end;

// This is only used is main.dsp now, and only for news.
// May want to make a special one for news instead.
define body tag list-pages in wiki
    (page :: <wiki-dsp>, do-body :: <function>)
    (tags :: false-or(<string>),
     order-by :: false-or(<string>),
     use-query-tags :: <boolean>)
  let tagged = get-query-value("tagged");
  let tags = iff(use-query-tags & instance?(tagged, <string>),
                 parse-tags(tagged),
                 iff(tags, parse-tags(tags), #[]));
  for (page in find-pages(tags: tags, order-by: creation-date-newer?))
    dynamic-bind(*page* = page)
      do-body();
    end;
  end for;
end;


// named methods

define named-method is-discussion-page? in wiki
    (page :: <wiki-dsp>)
  *page* & discussion-page?(*page*);
end;

define named-method latest-page-version? in wiki
    (page :: <wiki-dsp>)
  // TODO: Currently we assume the latest revision of the page is always
  //       stored in *pages*.
  *page* & *page* == element(*pages*, *page*.page-title, default: $unfound)
end;

define named-method page-tags in wiki
    (page :: <wiki-dsp>)
  iff(*page*,
      sort(*page*.page-tags, test: \=),
      #[])
end;


