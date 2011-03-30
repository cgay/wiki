Module: %wiki
Synopsis: Implement the storage protocol with a git back-end
Author: Carl Gay


// See wiki.dylan for the storage protocol generics.

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
define constant $git-author-regex :: <regex>
  = compile-regex("Author: .* <([^@])@.*>");

define variable *pages-directory* :: false-or(<directory-locator>) = #f;
define variable *users-directory* :: false-or(<directory-locator>) = #f;
define variable *groups-directory* :: false-or(<directory-locator>) = #f;


define class <git-storage> (<storage>)

  // The root directory of the wiki data repository, as a string.
  constant slot git-repository-root :: <directory-locator>,
    required-init-keyword: repository-root:;

  // User data is stored in a separate repository so that it can
  // be maintained separately (more securely) than other data.
  constant slot git-user-repository-root :: <directory-locator>,
    required-init-keyword: user-repository-root:;

  constant slot git-executable :: <file-locator>,
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

/// Make sure the git repository directories exist and have been
/// initialized as git repositories.
///
define method initialize-storage
    (storage :: <git-storage>) => ()
  ensure-directories-exist(storage.git-repository-root);
  ensure-directories-exist(storage.git-user-repository-root);

  // It is supposed to be safe to call "git init" on an already
  // initialized repository, so we don't check whether it has already
  // been done first.
  call-git(storage, "init");
  call-git(storage, "init", working-directory: storage.git-user-repository-root);

  *pages-directory* := subdirectory-locator(storage.git-repository-root, "pages");
  *users-directory* := subdirectory-locator(storage.git-user-repository-root, "users");
  *groups-directory* := subdirectory-locator(storage.git-repository-root, "groups");

  let created? = (ensure-directories-exist(*pages-directory*)
                  | ensure-directories-exist(*groups-directory*));
  if (created?)
    git-commit(storage, storage.git-repository-root, *admin-user*,
               "Created initial directories");
  end;

  let created? = ensure-directories-exist(*users-directory*);
  if (created?)
    git-commit(storage, storage.git-user-repository-root, *admin-user*,
               "Created initial directories");
  end;
end method initialize-storage;


//// Pages

/// Load a page from back-end storage.  'name' is the page title.
/// Return: version -- a git hash code (a string)
///
define method load
    (storage :: <git-storage>, class == <wiki-page>, title :: <string>,
     #key revision = #"newest")
 => (page :: <wiki-page>)
  let page-dir = git-page-storage-directory(storage, title);
  let content-file = file-locator(page-dir, $content);
  let commit :: <commit> = git-log-one(storage, content-file, revision);
  let hash = commit.commit-hash;
  let tags = git-load-blob(storage, file-locator(page-dir, $tags), hash);
  let acls = git-load-blob(storage, file-locator(page-dir, $acls), hash);
  let content = git-load-blob(storage, content-file, hash);
  let (owner, acls) = git-parse-acls(acls, title);
  make(<wiki-page>,
       creation-date: creation-date,
       title: title,
       content: content,
       comment: commit.commit-comment,
       owner: owner,
       author: find-user(commit.commit-author) | *admin-user*,
       revision: hash,
       tags: git-parse-tags(tags),
       access-controls: acls)
end method load;

define method store
    (storage :: <storage>, page :: <wiki-page>, author :: <wiki-user>,
     comment :: <string>)
 => (revision :: <string>)
  let page-dir = git-page-storage-directory(storage, page.page-title);
  ensure-directories-exist(page-dir);

  git-store-blob(file-locator(page-dir, $content), page.page-content);
  git-store-blob(file-locator(page-dir, $tags), tags-to-string(page.page-tags));
  git-store-blob(file-locator(page-dir, $acls), acls-to-string(page));

  git-commit(storage, page-dir, author, comment)
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

define function git-page-storage-directory
    (storage :: <git-storage>, title :: <string>)
 => (directory :: <directory-locator>)
  let len :: <integer> = title.size;
  if (len = 0)
    git-error("Zero length page title not allowed.");
  else
    // Use first three (or fewer) letters to divide pages into a broader
    // directory structure.
    let prefix = slice(title, 0, $page-prefix-size);
    if (len < $page-prefix-size)
      prefix := concatenate(prefix, make(<byte-string>,
                                         size: $page-prefix-size - len,
                                         fill: '_'));
    end;
    subdirectory-locator(*pages-directory*, $default-sandbox-name, prefix, title)
  end
end function git-page-storage-directory;



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
  do-object-files(*users-directory*, <wiki-user>, load-user);
  reverse!(users)
end method load-all;

define function git-parse-user
    (creation-date :: <string>, line :: <string>) => (user :: <wiki-user>)
  let (name, real-name, admin?, password, email, activation-key, activated?)
    = apply(values, split(line, ':'));
  make(<wiki-user>,
       creation-date: git-parse-date(creation-date),
       name: name,
       real-name: iff(empty?(real-name), #f, real-name),
       password: password,  // in base-64 (for now)
       email: email,    // in base-64
       administrator?: git-parse-boolean(admin?),
       activation-key: activation-key,
       activated?: git-parse-boolean(activated?))
end function git-parse-user;

define method store
    (storage :: <storage>, user :: <wiki-user>, author :: <wiki-user>,
     comment :: <string>)
 => (revision :: <string>)
  let file = git-user-storage-file(storage, user.user-name);
  ensure-directories-exist(file);
  git-store-blob(file,
                 sformat("%s\n%s:%s:%s:%s:%s:%s:%s\n",
                         git-encode-date(user.creation-date),
                         user.user-name,
                         user.%user-real-name | "",
                         git-encode-boolean(user.administrator?),
                         user.user-password,  // in base-64 (for now)
                         user.user-email,     // already in base-64
                         user.user-activation-key,
                         git-encode-boolean(user.user-activated?)));
  git-commit(storage, file, author, comment)
end method store;

define function git-user-storage-file
    (storage :: <git-storage>, name :: <string>)
 => (pathname :: <string>)
  file-locator(subdirectory-locator(*users-directory*, slice(name, 0, 1)),
               name)
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
          with-open-file(stream = file, direction: #"input")
            let creation-date    = read-line(stream, on-end-of-stream: #f);
            let people           = read-line(stream, on-end-of-stream: #f);
            let description-size = read-line(stream, on-end-of-stream: #f);
            let description      = read-to-end(stream);
            groups := pair(git-parse-group(creation-date,
                                           people, description-size, description),
                           groups);
          end;
        end;
  do-object-files(*groups-directory*, <wiki-group>, load-group);
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
    (storage :: <storage>, group :: <wiki-group>, author :: <wiki-user>,
     comment :: <string>)
 => (revision :: <string>)
  let group-file = git-group-storage-file(storage, group.group-name);
  ensure-directories-exist(group-file);
  git-store-blob(group-file,
                 sformat("%s\n%s:%s:%s\n%d\n%s\n",
                         git-encode-date(group.creation-date),
                         group.group-name,
                         group.group-owner.user-name,
                         join(map(user-name, group.group-members), ":"),
                         integer-to-string(group.group-description.size),
                         group.group-description));
  git-commit(storage, group-file, author, comment)
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

define function git-group-storage-file
    (storage :: <git-storage>, name :: <string>)
 => (pathname :: <string>)
  file-locator(subdirectory-locator(*groups-directory*, slice(name, 0, 1)),
               name)
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
    = concatenate(as(<string>, storage.git-executable),
                  " ",
                  iff(format-args,
                      apply(sformat, command-fmt, format-args),
                      command-fmt));
  format-out("Running command %s\n", command);
  let (exit-code, signal, child, stdout-stream, stderr-stream)
    = run-application(command,
                      asynchronous?: #f,
                      working-directory: working-directory | storage.git-repository-root,
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

define function git-load-blob
    (storage :: <git-storage>, pathname :: <string>, revision)
 => (blob :: <string>)
  let (stdout, stderr, exit-code)
    = call-git(storage,
               sformat("show %s",
                       if (revision = #"newest")
                         // TODO: also return the revision
                         sformat("master:%s", pathname)
                       else
                         TODO
                       end));
  stdout
end function git-load-blob;

define function git-store-blob
    (file :: <file-locator>, blob :: <string>)
 => ()
  with-open-file (stream = file, direction: #"output", if-exists: #"overwrite")
    write(blob, stream);
  end;
end function git-store-blob;

/// Parse the content of the "acls" file into an '<acls>' object.
/// See README.rst for a description of the "acls" file format.
///
define function git-parse-acls
    (blob :: <string>, title :: <string>)
 => (owner :: <wiki-user>, acls :: <acls>)
  local method parse-rule(rule)
          let action = select (rule[0])
                         '+' => $allow;
                         '-' => $deny;
                         otherwise =>
                           git-error("Invalid access spec, %=, in ACLs for page %s",
                                     rule[0], title);
                       end;
          let name = slice(rule, 1, #f);
          let target = select(name by \=)
                         "anyone" => $anyone;
                         "trusted" => $trusted;
                         "owner" => $owner;
                         otherwise =>
                           find-user(name)
                           | find-group(name)
                           | git-error("Invalid name spec, %=, in ACLs for page %s",
                                       name, title);
                       end;
          list(action, target)
        end;
  local method rules (line)
          let rules = map(parse-rule, slice(split(line, ','), 1, #f));
          ~empty?(rules) & rules
        end;
  let lines = split(blob, $newline-regex);
  let owner = find-user(slice(lines[0], "owner: ".size, #f))
              | *admin-user*;
  let view-content   = rules(lines[1]) | $default-access-controls.view-content-rules;
  let modify-content = rules(lines[2]) | $default-access-controls.modify-content-rules;
  let modify-acls    = rules(lines[3]) | $default-access-controls.modify-acls-rules;

  values(owner,
         make(<acls>,
              view-content: view-content,
              modify-content: modify-content,
              modify-acls: modify-acls))
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
    (root :: <directory-locator>,
     class :: subclass(<wiki-object>),
     fun :: <function>)
 => ()
  local method do-object-dir (directory, name, type)
          // called once for each file/dir in a prefix directory
          if (class = <wiki-page> & type = #"directory")
            fun(subdirectory-locator(directory, name));
          elseif (type = #"file")
            fun(file-locator(directory, name));
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

define function git-commit
    (storage :: <git-storage>, locator :: <locator>, author :: <wiki-user>,
     comment :: <string>)
 => (revision :: <string>)
  // TODO: Don't want to put the real user email address in the author field,
  //       so probably need to use a (configurable?) fake address of some sort.
  //       Do I need to maintain the git authorsfile also?
  let (stdout, stderr, exit-code)
    = call-git(storage,
               sformat("commit --author \"%s <%s@opendylan.org>\" -m \"%s\" %s",
                       author.user-real-name,
                       author.user-name,
                       comment,
                       as(<string>, locator)));
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

define class <commit> (<object>)
  constant slot commit-hash    :: <string>, required-init-keyword: hash:;
  constant slot commit-author  :: <string>, required-init-keyword: author:;
  constant slot commit-date    :: <date>,   required-init-keyword: date:;
  constant slot commit-comment :: <string>, required-init-keyword: comment:;
end;

define function git-log-one
    (storage :: <git-storage>, file :: <file-locator>, revision :: <string>)
 => (commit :: <commit>)
  let (stdout, stderr, exit-code)
    = call-git(storage,
               sformat("log -1 --log-size --date=iso -- %s",
                       as(<string>, file)));

  let lines = split(stdout, "\n");
  let commit-line = lines[0];
  let log-size-line = lines[1]; // Note: includes author and date line lengths
  let author-line = lines[2];
  let date-line = lines[3];
  let comment = trim(join(slice(lines, 4, #f), "\n"));

  local method nth-word (line :: <string>, n :: <integer>) => (word :: <string>)
          split(line, ' ')[n]
        end;

  let hash = nth-word(commit-line, 1);
  let log-size = string-to-integer(nth-word(log-size-line, 3));
  let date = make(<date>, iso8601-string: slice(date-line, "Date: ".size, #f));

  let match = regex-search($git-author-regex, author-line);
  let author = match-group(match, 1);

  make(<commit>, hash: hash, author: author, date: date, comment: comment)
end function git-log-one;

define function tags-to-string
    (tags :: <sequence>) => (string :: <string>)
  join(tags, "\n")
end;

// This function must match string-to-acls
define function acls-to-string
    (page :: <wiki-page>) => (string :: <string>)
  local method rule-to-string (rule :: <rule>) => (string :: <string>)
          let target = rule.rule-target;
          concatenate(select (rule.rule-target)
                        $allow => "+";
                        $deny => "-";
                      end,
                      case
                        target = $anyone => "$any";
                        target = $trusted => "$trusted";
                        target = $owner => "$owner";
                        instance?(target, <wiki-user>) => target.user-name;
                        instance?(target, <wiki-group>) => target.group-name;
                      end)
        end;
  let acls :: <acls> = page.access-controls;
  sformat("owner: %s\nview-content: %s\nmodify-content: %s\nmodify-acls: %s",
          page.page-owner.user-name,
          join(acls.view-content-rules, ",", key: rule-to-string),
          join(acls.modify-content-rules, ",", key: rule-to-string),
          join(acls.modify-acls-rules, ",", key: rule-to-string))
end function acls-to-string;

define method file-locator
    (directory :: <directory-locator>, name :: <string>)
 => (file :: <file-locator>)
  merge-locators(as(<file-locator>, name), directory)
end;


