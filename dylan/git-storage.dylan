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

  // User data is stored in a separate repository so that it can
  // be maintained separately (more securely) than other data.
  slot git-user-repository-root :: <string>,
    required-init-keyword: user-repository-root:;

  slot git-executable :: <string>,
    required-init-keyword: executable:;

  slot git-branch :: <string>,
    required-init-keyword: branch:;

end class <git-storage>;


define class <git-storage-error> (<storage-error>)
end;

define function git-error
    (fmt :: <string>, #rest args)
  signal(make(<git-storage-error>,
              format-string: fmt,
              format-arguments: args))
end;

/// Run the given git command with CWD set to the wiki data repository root.
///
define function git
    (storage :: <git-storage>, command-fmt :: <string>,
     #key error? :: <boolean> = #t,
          format-args = #f)
 => (exit-code :: <integer>,
     stdout :: <string>,
     stderr :: <string>)
  let command
    = concatenate(storage.git-executable,
                  " ",
                  iff(format-args,
                      apply(format-to-string, command-fmt, format-args),
                      command-fmt));
  format-out("Running command %s\n", command);
  let (exit-code, signal, child, stdout-stream, stderr-stream)
    = run-application(command,
                      asynchronous?: #f,
                      working-directory: storage.git-repository-root,
                      output: #"stream",
                      error: #"stream");
  // TODO:
  // I'm not going to worry about buffering problems this might run into
  // due to massive amounts of output right now, but something more robust
  // will be needed eventually.
  let stdout = read-to-end(stdout-stream);
  let stderr = read-to-end(stderr-stream);
  if (error? & (exit-code ~= 0))
    git-error("Error running git command %=:\n"
              "exit code: %=\n",
              "stdout: %s\n",
              "stderr: %s\n",
              exit-code, stdout, stderr);
  else
    values(exit-code, stdout, stderr)
  end
end function git;


//// Initialization

/// Make sure the git repository directory exists and has been
/// initialized as a git repo.
///
define method initialize-storage
    (storage :: <git-storage>) => ()
  // It is supposed to be safe to call "git init" on an already
  // initialized repository, so we don't check whether it has already
  // been done first.
  git(storage, "init");
end method initialize-storage;


//// Pages

/// Load a page from back-end storage.  'name' is the page title.
/// Return: version -- a git hash code (a string)
///
define method load
    (storage :: <git-storage>, class == <wiki-page>, title :: <string>,
     #key revision = #"newest")
 => (page :: <wiki-page>)
  let page-dir = git-page-directory(title);

  // git show master:<page-path>/content
  // Could also use:
  //   $ echo git-backend:config.xml | git cat-file --batch
  //   b0a7106bff6f0249b9e2ea0e5e4d0f282d5217e1 blob 1436
  //   <?xml version="1.0"?>...
  // Probably need to use "git log" to get the comment, author, and revision,
  // and then use "git cat-file" or "git show" to get the content.

  local method show (filename)
          format-to-string("show %s",
                           make-git-show-arg(storage, page-dir, filename, revision))
        end;
  let tags = call-git(storage, show($tags));
  let acls = call-git(storage, show($acls));
  let content = call-git(storage, show($content));
  make(<wiki-page>,
       title: title,
       content: content,
       comment: comment,
       owner: owner,
       author: author,
       revision: revision,
       tags: git-parse-tags(tags-blob),
       access-controls: git-parse-acls(acls-blob))
end method load;

/// Return the git directory for the given page, relative to the
/// repository root.
define function git-page-directory
    (title :: <string>) => (directory :: <string>)
  let len :: <integer> = title.size;
  if (len = 0)
    git-error("Zero length page title not allowed.");
  else
    // Use first three (or fewer) letters to divide pages into a broader
    // directory structure.
    // TODO: for now we hard-code the "main" domain, until we support
    //       multiple domains/wikis/whatever.
    let tlc = slice(title, 0, 3);
    if (len < 2)
      tlc := concatenate(tlc, "-");
    elseif (len < 3)
      tlc := concatenate(tlc, "--");
    end;
    format-to-string("domains/main/%s/%s", tlc, title)
  end
end;


define method store
    (storage :: <storage>, page :: <wiki-page>, comment :: <string>)
 => (revision :: <string>)
  TODO;
  // Create the directories
  // Write the files
  // git commit
  revision
end method store;

define method delete
    (storage :: <storage>, page :: <wiki-page>, comment :: <string>)
 => ()
  TODO;
end;

define method rename
    (storage :: <storage>, page :: <wiki-page>, new-name :: <string>,
     comment :: <string>)
 => ()
  TODO;
end;



//// Users

/// Load all users from back-end storage.
/// Returns a collection of <wiki-user>s.
/// See ../README.rst for a description of the file format.
///
define method load-all
    (storage :: <storage>, class == <wiki-user>)
 => (users :: <collection>)
  let pathname = git-user-file-pathname(storage);
  with-open-file(stream = pathname, direction: #"input")
    iterate loop (line = read-line(stream, on-end-of-stream: #f))
end method load-all;

define method load
    (storage :: <storage>, class == <wiki-user>, name :: <string>, #key)
 => (obj :: <wiki-user>)
  TODO;
end method load;

define method store
    (storage :: <storage>, user :: <wiki-user>, comment :: <string>)
 => (revision :: <string>)
  TODO;
end method store;


define method delete
    (storage :: <storage>, user :: <wiki-user>, comment :: <string>)
 => ()
  TODO;
end;

define method rename
    (storage :: <storage>, user :: <wiki-user>, new-name :: <string>,
     comment :: <string>)
 => ()
  TODO;
end;



//// Groups

define method load-all
    (storage :: <storage>, class == <wiki-group>)
 => (groups :: <collection>)
  TODO
end;

define method load
    (storage :: <storage>, class == <wiki-group>, name :: <string>, #key)
 => (group :: <wiki-group>)
  TODO;
end method load;

define method store
    (storage :: <storage>, group :: <wiki-group>, comment :: <string>)
 => (revision :: <string>)
  TODO;
end method store;


define method delete
    (storage :: <storage>, group :: <wiki-group>, comment :: <string>)
 => ()
  TODO;
end method delete;

define method rename
    (storage :: <storage>, group :: <wiki-group>, new-name :: <string>,
     comment :: <string>)
 => ()
  TODO;
end method rename;



//// Utilities

/// Make an argument to pass to the 'git show' command.
///
define function make-git-show-arg
    (storage :: <git-storage>, page-directory :: <string>, filename :: <string>, revision)
 => (arg :: <string>)
  if (revision = #"newest")
    format-to-string("%s:%s/%s", storage.git-branch, page-directory, filename)
  else
    TODO
  end;
end;


define constant $newline-regex :: <regex> = compile-regex("[\r\n]+");

/// Parse the content of the "acls" file into an '<acls>' object.
/// See README.rst for a description of the "acls" file format.
///
define function git-parse-acls
    (blob :: <string>) => (acls :: <acls>)
  local method parse-rule(rule)
          let (access, name) = apply(values, split(rule, '@'));
          let access = select (access by \=)
                         "allow" => allow:;
                         "deny" => deny:;
                         otherwise =>
                           git-error("Invalid access spec, %=, in ACLs for page %s",
                                     access, title);
                       end;
          let name = select(name by \=)
                       "anyone" => $anyone;
                       "trusted" => $trusted;
                       "owner" => $owner;
                       otherwise =>
                         git-error("Invalid name spec, %=, in ACLs for page %s",
                                   name, title);
                     end;
          list(access, name)
        end;
  let lines = split(blob, $newline-regex);
  let view-content = #f;
  let modify-content = #f;
  let modify-acls = #f;
  let owner = #f;
  for (line in lines)
    let parts = split(line, ',');
    if (parts.size > 1)
      let key = trim(parts[0]);
      select (key by \=)
        "owner:" =>
          owner := find-user(trim(parts[1]));
        "modify-content:" =>
          modify-content := map(parse-rule, slice(parts, 1, #f));
        "modify-acls:" =>
          modify-acls := map(parse-rule, slice(parts, 1, #f));
        "view-content:" =>
          view-content := map(parse-rule, slice(parts, 1, #f));
        otherwise =>
          #f;
      end select;
    end if;
  end for;
  make(<acls>,
       view-content: view-content | $default-access-controls.view-content-rules,
       modify-content: modify-content | $default-access-controls.modify-content-rules,
       modify-acls: modify-acls | $default-access-controls.modify-acls-rules)
end function git-parse-acls;

define function git-parse-tags
    (blob :: <string>) => (tags :: <sequence>)
  // one tag per line...
  choose(complement(empty?),
         remove-duplicates!(map(trim, split(blob, $newline-regex)),
                            test: \=))
end;
