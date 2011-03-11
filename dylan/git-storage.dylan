Module: %wiki
Synopsis: Implement the storage protocol with a git back-end
Author: Carl Gay


// See wiki.dylan for the storage protocol generics.

// File names inside a git page directory
define constant $content :: <byte-string> = "content";
define constant $tags :: <byte-string> = "tags";
define constant $acls :: <byte-string> = "acls";


define class <git-storage> (<storage>)

  // The root directory of the wiki data repository, as a string.
  slot git-repository-root :: <string>,
    required-init-keyword: repository-root:;

  // TODO: make this configurable
  slot git-executable :: <string> = "git",
    init-keyword: executable:;

  // TODO: make this configurable
  slot git-branch :: <string> = "master",
    init-keyword: branch:;

end;


define class <git-storage-error> (<storage-error>)
end;

define function git-error
    (fmt :: <string>, #rest args)
  signal(make(<git-storage-error>,
              format-string: fmt,
              format-arguments: args))
end;



//// Pages

/// Load a page from back-end storage.  'name' is the page title.
/// Return: version -- a git hash code (a string)
///
define method load
    (storage :: <git-storage>, class == <wiki-page>, name :: <string>,
     #key version = #"newest")
 => (page :: <wiki-page>)
  let page-dir = git-page-directory(title);

  // TODO: load tags, owner, acls

  // git show master:<page-path>/content
  let command = vector(storage.git-executable,
                       "show",
                       make-git-show-arg(storage, title, version, $content));
  let (exit-code, signal, child, stdout, stderr)
    = run-application(command,
                      input: #"null",
                      output: #"stream",
                      asynchronous?: #t,
                      under-shell?: #f,
                      inherit-console?: #t,
                      working-directory: storage.git-repository-root
                      //environment: env
                      );
  if (exit-code = 0)
    make(<wiki-page>,
         title: title,
         content: read-to-end(stdout))
  else
    git-error("Command failed: %s, exit-code: %s, signal: %s",
              command, exit-code, signal);
  end;
end method load;

/// Return the git directory for the given page, relative to the
/// repository root.
define function git-page-directory
    (title :: <string>) => (directory :: <string>)
  if (title.size = 0)
    git-error("Zero length page title not allowed.");
  else
    // Use first three letters to divide pages into a broader
    // directory structure.
    // TODO: for now we hard-code the "main" domain, until we support
    //       multiple domains/wikis/whatever.
    format-to-string("domains/main/%s/%s", slice(title, 0, 3), title)
  end
end;


/// Store the given page as the newest version.
/// Return the version, which may be any object.
/// 
define method store
    (storage :: <storage>, page :: <wiki-page>) => (version);
  TODO
end;




//// Users

/// Load all users from back-end storage.
/// Returns a collection of <wiki-user>s.
///
define method load-users
    (storage :: <storage>) => (users :: <collection>);
  TODO
end;

/// Store the given user account.
///
define method store-user
    (storage :: <storage>, user :: <wiki-user>) => ();
  TODO
end;


//// Groups

/// Load all groups from back-end storage.
/// Returns a collection of <wiki-group>s.
///
define method load-groups
    (storage :: <storage>) => (groups :: <collection>);
  TODO
end;

/// Store the given group.
///
define method store-group
    (storage :: <storage>, group :: <wiki-group>) => ();
  TODO
end;



//// Utilities

define function make-git-show-arg
    (storage :: <git-storage>, title :: <string>, version)
 => (arg :: <string>)
  // TODO: support for version
  format-to-string("%s:%s/%s",
                   storage.git-branch,
                   git-page-directory(title),
                   filename)
end;


