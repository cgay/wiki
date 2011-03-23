Module: %wiki
Synopsis: Implement the storage protocol with a git back-end
Author: Carl Gay


// See wiki.dylan for the storage protocol generics.

// Pathname hacking is generally done with strings, not locators.

// TODO: anywhere that creates a directory or file needs to "git add" it.

// TODO: locking strategy.  Ensure that only one instance of the wiki
//       application can run for a given repository. Then load-all-users/groups
//       can be done safely at startup. Then there could be one file lock per
//       page/group/user.  File locks are needed because these objects need to
//       be locked while the user is busily editing them in some web page.
//       This could get arbitrarily complicated and needs some research first.
//       I will proceed for now without locking at all.  Weee!

// TODO: error handling.  Think "disk error".

define constant $user-prefix-size :: <integer> = 1;
define constant $group-prefix-size :: <integer> = 1;
define constant $page-prefix-size :: <integer> = 3;

// For now there is no way to create new "sandboxes"; that level
// in the directory hierarchy exists only for future expansion.
define constant $default-sandbox-name :: <string> = "main";

// File names inside a git page directory
define constant $content :: <byte-string> = "content";
define constant $tags :: <byte-string> = "tags";
define constant $acls :: <byte-string> = "acls";

define constant sformat = format-to-string;

define constant $newline-regex :: <regex> = compile-regex("[\r\n]+");
define constant $whitespace-regex :: <regex> = compile-regex("[\r\n\t]");


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

end class <git-storage>;


define class <git-storage-error> (<storage-error>)
end;

define function git-error
    (fmt :: <string>, #rest args)
  signal(make(<git-storage-error>,
              format-string: fmt,
              format-arguments: args))
end;


//// Initialization

/// Make sure the git repository directory exists and has been
/// initialized as a git repo.
///
define method initialize-storage
    (storage :: <git-storage>) => ()
  // It is supposed to be safe to call "git init" on an already
  // initialized repository, so we don't check whether it has already
  // been done first.
  call-git(storage, "init");
end method initialize-storage;


//// Pages

/// Return the git directory for the given page, relative to the
/// repository root.
define function git-page-storage-pathname
    (title :: <string>) => (directory :: <string>)
  let len :: <integer> = title.size;
  if (len = 0)
    git-error("Zero length page title not allowed.");
  else
    // Use first three (or fewer) letters to divide pages into a broader
    // directory structure.
    // TODO: for now we hard-code the "main" domain, until we support
    //       multiple domains/wikis/whatever.
    let prefix = slice(title, 0, $page-prefix-size);
    if (len < $page-prefix-size)
      prefix := concatenate(prefix, make(<byte-string>,
                                         size: $page-prefix-size - len,
                                         fill: '_'));
    end;
    sformat("pages/%s/%s/%s", $default-sandbox-name, prefix, title)
  end
end function git-page-storage-pathname;

/// Load a page from back-end storage.  'name' is the page title.
/// Return: version -- a git hash code (a string)
///
define method load
    (storage :: <git-storage>, class == <wiki-page>, title :: <string>,
     #key revision = #"newest")
 => (page :: <wiki-page>)
  let page-dir = git-page-storage-pathname(title);
  let tags = git-get-blob(storage, pathname-join(page-dir, $tags), revision);
  let acls = git-get-blob(storage, pathname-join(page-dir, $acls), revision);
  let content = git-get-blob(storage, pathname-join(page-dir, $content), revision);
  let (owner, acls) = git-parse-acls(acls, title);
  make(<wiki-page>,
       title: title,
       content: content,
       comment: comment,
       owner: owner,
       author: author,
       revision: revision,
       tags: git-parse-tags(tags),
       access-controls: acls)
end method load;

define method store
    (storage :: <storage>, page :: <wiki-page>, comment :: <string>)
 => (revision :: <string>)
  // Create the directories
  // Write the files
  // git commit
  let pathname :: <string> = git-page-storage-pathname(storage, page);
  let dir? = file-exists?(dirname(pathname));
  if (~dir?)
    create-directory(dirname(pathname));
  end;
  with-open-file (stream = pathname, direction: #"output",
                  if-exists: #"overwrite")
    git-write-user(stream, user);
  end;
  git-commit(storage, pathname, comment)
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

// All users are loaded from storage at startup and they are written
// to storage individually as they're created or changed.  Therefore
// there is no need for 'load' or 'store-all' methods.

/// Load all users from back-end storage.
/// Returns a collection of <wiki-user>s.
/// See ../README.rst for a description of the file format.
///
define method load-all
    (storage :: <storage>, class == <wiki-user>)
 => (users :: <collection>)
  let users = #();
  local method load-user(pathname :: <file-locator>)
          with-open-file(stream = pathname, direction: #"input")
            let creation-date = read-line(stream, on-end-of-stream: #f);
            let line = read-line(stream, on-end-of-stream: #f);
            users := pair(git-parse-user(creation-date, line),
                          users);
          end;
        end;
  do-object-files(git-user-storage-pathname(storage), load-user);
  reverse!(users)
end method load-all;

define function git-parse-user
    (creation-date :: <string>, line :: <string>) => (user :: <wiki-user>)
  let (name, admin?, password, email, activation-key, activated?)
    = apply(values, split(line, ':'));
  make(<wiki-user>,
       creation-date: git-parse-date(creation-date),
       name: name,
       password: password,  // in base-64 (for now)
       email: email,    // in base-64
       administrator?: git-parse-boolean(admin?),
       activation-key: activation-key,
       activated?: git-parse-boolean(activated?))
end function git-parse-user;

define method store
    (storage :: <storage>, user :: <wiki-user>, comment :: <string>)
 => (revision :: <string>)
  let pathname :: <string> = git-user-storage-pathname(storage, user);
  let dir? = file-exists?(dirname(pathname));
  if (~dir?)
    create-directory(dirname(pathname));
  end;
  with-open-file (stream = pathname, direction: #"output",
                  if-exists: #"overwrite")
    git-write-user(stream, user);
  end;
  git-commit(storage, pathname, comment)
end method store;

define function git-write-user
    (stream :: <stream>, user :: <wiki-user>) => ()
  format(stream,
         "%s\n%s:%s:%s:%s:%s:%s\n",
         git-encode-date(user.creation-date),
         user.user-name,
         git-encode-boolean(user.administrator?),
         user.user-password,  // in base-64 (for now)
         user.user-email,     // already in base-64
         user.user-activation-key,
         git-encode-boolean(user.user-activated?));
end function git-write-user;

define function git-user-storage-pathname
    (storage :: <git-storage>, user :: <wiki-user>)
 => (pathname :: <string>)
  sformat("users/%c/%s", user.user-name[0], user.user-name)
end;


//// Groups

// All groups are loaded from storage at startup and they are written
// to storage individually as they're created or changed.  Therefore
// there is no need for 'load' or 'store-all' methods.

/// Load all users from back-end storage.
/// Returns a collection of <wiki-user>s.
/// See ../README.rst for a description of the file format.
///
define method load-all
    (storage :: <storage>, class == <wiki-group>)
 => (groups :: <collection>)
  let groups = #();
  local method load-group(file :: <file-locator>)
          with-open-file(stream = pathname, direction: #"input")
            let creation-date    = read-line(stream, on-end-of-stream: #f);
            let people           = read-line(stream, on-end-of-stream: #f);
            let description-size = read-line(stream, on-end-of-stream: #f);
            let description      = read-to-end(stream);
            groups := pair(git-parse-group(creation-date,
                                           people, description-size, description),
                           groups);
          end;
        end;
  do-object-files(git-group-storage-pathname(storage), load-group);
  reverse!(groups)
end;

define function git-parse-group
    (creation-date :: <string>,
     people :: <string>,
     description-size :: <string>,
     description :: <string>)
 => (user :: <wiki-group>)
  let (group-name, owner-name, #rest member-names) = apply(values, split(people, ':'));
  let desc-size = string-to-integer(trim(description-size));
  let description = slice(description, 0, desc-size);
  make(<wiki-group>,
       creation-date: git-parse-date(creation-date),
       name: group-name,
       owner: find-user(owner-name),
       members: map(find-user, member-names),
       description: description)
end function git-parse-group;

define method store
    (storage :: <storage>, group :: <wiki-group>, comment :: <string>)
 => (revision :: <string>)
  let pathname :: <string> = git-group-storage-pathname(storage, group);
  let dir? = file-exists?(dirname(pathname));
  if (~dir?)
    create-directory(dirname(pathname));
  end;
  with-open-file (stream = pathname, direction: #"output",
                  if-exists: #"overwrite")
    git-write-group(stream, group);
  end;
  git-commit(storage, pathname, comment)
end method store;

define method git-write-group
    (stream :: <stream>, group :: <wiki-group>) => ()
  format(stream,
         "%s\n%s:%s:%s\n%d\n%s\n",
         git-encode-date(group.creation-date),
         group.group-name,
         group.group-owner.user-name,
         join(map(user-name, group.group-members), ":"),
         group.group-description.size,
         group.group-description);
end method git-write-group;

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

define function git-group-storage-pathname
    (storage :: <git-storage>, group :: <wiki-group>)
 => (pathname :: <string>)
  sformat("groups/%c/%s", group.group-name[0], group.group-name)
end;



//// Utilities

/// Run the given git command with CWD set to the wiki data repository root.
///
define function call-git
    (storage :: <git-storage>, command-fmt :: <string>,
     #key error? :: <boolean> = #t,
          format-args = #f,
          working-directory = #f)
 => (stdout :: <string>,
     stderr :: <string>,
     exit-code :: <integer>)
  let command
    = concatenate(storage.git-executable,
                  " ",
                  iff(format-args,
                      apply(sformat, command-fmt, format-args),
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
    values(stdout, stderr, exit-code)
  end
end function call-git;

// git show master:<page-path>/content
// Could also use:
//   $ echo git-backend:config.xml | git cat-file --batch
//   b0a7106bff6f0249b9e2ea0e5e4d0f282d5217e1 blob 1436
//   <?xml version="1.0"?>...
// Probably need to use "git log" to get the comment, author, and revision,
// and then use "git cat-file" or "git show" to get the content.

define function git-get-blob
    (storage :: <git-storage>, pathname :: <string>, revision)
 => (blob :: <string>)
  let (stdout, stderr, exit-code)
    = call-git(storage,
               sformat("show %s",
                       if (revision = #"newest")
                         sformat("master:%s", pathname)
                       else
                         TODO
                       end));
  stdout
end function git-get-blob;

/// Parse the content of the "acls" file into an '<acls>' object.
/// See README.rst for a description of the "acls" file format.
///
define function git-parse-acls
    (blob :: <string>, title :: <string>) => (acls :: <acls>)
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
  values(owner,
         make(<acls>,
              view-content: view-content | $default-access-controls.view-content-rules,
              modify-content: modify-content | $default-access-controls.modify-content-rules,
              modify-acls: modify-acls | $default-access-controls.modify-acls-rules))
end function git-parse-acls;

define function git-parse-tags
    (blob :: <string>) => (tags :: <sequence>)
  // one tag per line...
  choose(complement(empty?),
         remove-duplicates!(map(trim, split(blob, $newline-regex)),
                            test: \=))
end;

define inline function git-encode-boolean
    (bool :: <boolean>) => (bool :: <string>)
  iff(bool, "T", "F")
end;

define inline function git-parse-boolean
    (string :: <string>) => (bool :: <boolean>)
  iff(string = "T", #t, #f)
end;

define inline function git-encode-date
    (date :: <date>) => (date :: <string>)
  as-iso8601-string(date)
end;

define inline function git-parse-date
    (date :: <string>) => (date :: <date>)
  make(<date>, iso8601-string: date)
end;

/// Iterate over an object directory hierarchy applying 'fun' to each one in turn.
/// i.e., each page directory, user file, or group file.
///
define function do-object-files
    (root :: <string>, class :: subclass(<wiki-object>), fun :: <function>) => ()
  local method do-object-dir (directory, name, type)
          // called once for each file/dir in a prefix directory
          if (class = <wiki-page> & type = #"directory")
            fun(merge-locators(as(<directory-locator>, name), directory));
          elseif (type = #"file")
            fun(merge-locators(as(<file-locator>, name), directory));
          end;
        end,
        method do-prefix-dir (directory, name, type)
          // called once per prefix directory
          if (type = #"directory")
            do-directory(do-object-dir, directory)
          end;
        end;
  do-directory(do-prefix-dir, root);
end function do-object-files;

/// Commit a file or directory.
/// Arguments:
///   pathname - a path relative to the repository root
define function git-commit
    (storage :: <git-storage>, pathname :: <string>, comment :: <string>)
 => (revision :: <string>)
  let (stdout, stderr, exit-code)
    = call-git(storage, sformat("commit -m '%s' %s", comment, pathname));
  // The stdout from git commit looks like this:
  //     [git-backend 804b716] ...commit comment...
  //     1 files changed, 64 insertions(+), 24 deletions(-)
  let open-bracket = find-key(stdout, curry(\=, '['));
  let close-bracket = find-key(stdout, curry(\=, ']'));
  if (~open-bracket | ~close-bracket)
    git-error("Unexpected output from the 'git commit' command: %=", stdout);
  else
    let parts = split(slice(stdout, open-bracket + 1, close-bracket), $whitespace-regex);
    if (parts.size ~= 2)
      git-error("Unexpected output from the 'git commit' command: %=", stdout);
    else
      let (branch, hash) = apply(values, parts);
      hash
    end;
  end;
end function git-commit;
