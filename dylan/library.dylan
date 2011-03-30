Module: dylan-user
Author: turbo24prg

define library wiki
  use collection-extensions,
    import: { sequence-diff };
  use collections,
    import: { set, table-extensions };
  use command-line-parser;
  use common-dylan,
    import: { common-extensions };
  use dsp;
  use dylan;
  use graphviz-renderer;
  use http-common;
  use io;
  use koala;
  use network;
  use smtp-client;
  use strings;
  use string-extensions;
  use system,
    import: {
      date,
      file-system,
      locators,
      operating-system,
      threads
      };
  use regular-expressions;
  use uri;
  use web-framework;
  use xml-parser;
  use xml-rpc-client;

/* for the monday parser, currently unused
  use grammar;
  use simple-parser;
  use regular;
*/

  use uncommon-dylan;

  export
    wiki,
    %wiki;   // for the test suite
end library wiki;

define module wiki
  create
    add-wiki-responders;
end;

define module %wiki
  use changes,
    prefix: "wf/",
    exclude: { <uri> };
  use command-line-parser;
  use common-extensions,
    exclude: { format-to-string };
  use date;
  use dsp;
  use dylan;
  use file-system;
  use format;
  use format-out;
  use http-common,
    exclude: { remove-attribute };
  use koala;
  use locators,
    exclude: { <http-server>, <url> };
  use operating-system;
  use permission;
  use sequence-diff;
  use set,
    import: { <set> };
  use simple-xml;
  use smtp-client;
  use streams;
  use strings,
    import: { trim };
  use substring-search;
  use table-extensions,
    rename: { table => make-table };
  use threads;
  use regular-expressions;
  use uncommon-dylan;
  use uri;
  use users,
    export: {
      <wiki-user>,
      user-name,
      user-password,
      user-email,
      administrator?,
      user-activation-key,
      user-activated?
      };

  use web-framework,
    prefix: "wf/";
  use wiki;
  use xml-parser,
    prefix: "xml/";
  use xml-rpc-client;

  // for the monday parser, currently unused
/*
  use simple-parser;
  use grammar;
  use simple-lexical-scanner;
*/

  use graphviz-renderer,
    prefix: "gvr/";

  export
    // ACLs
    <acls>,
    $view-content, $modify-content, $modify-acls,
    $anyone, $trusted, $owner,
    $default-access-controls,
    has-permission?;

  // Storage
  export
    <storage>,
    <git-storage>,
    <storage-error>,
    initialize-storage,
    load,
    load-all,
    store,
    delete,
    rename;
    
  // Groups
  export
    <wiki-group>;

  // Pages
  export
    <wiki-page>;

  // Users (the other bindings are exported from the users module, above)
  export
    <wiki-user>,
    user-real-name;

end module %wiki;

