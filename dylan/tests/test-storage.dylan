Module: wiki-test-suite
Synopsis: Tests of the storage protocol

// This should be the only function here that depends on the git back-end.
// TODO: make paths configurable
define function make-storage
    () => (storage :: <storage>)
  let base = as(<directory-locator>, "c:/tmp/storage-test-suite");
  let main = subdirectory-locator(base, "main-storage");
  let user = subdirectory-locator(base, "user-storage");
  if (file-exists?(base))
    test-output("Deleting base directory %s\n", as(<string>, base));
    delete-directory(base, recursive?: #t);
  end;
  let git-exe = as(<file-locator>, "c:\\Program Files\\Git\\bin\\git.exe");
  let storage = make(<git-storage>,
                     repository-root: main,
                     user-repository-root: user,
                     executable: git-exe);
  // There are some chicken & egg problems with *admin-user* and initialize-storage...
  init-admin-user(storage);
  initialize-storage(storage);
  store(storage, *admin-user*, *admin-user*, "init-admin-user");
  storage
end function make-storage;

define function init-storage
    () => (storage :: <storage>)
  let storage = make-storage();
  initialize-storage(storage);
  storage
end;

define function init-admin-user
    (storage :: <storage>) => (user :: <wiki-user>)
  *admin-user* := make(<wiki-user>,
                       name: "administrator",
                       real-name: "Administrator",
                       password: "secret",
                       email: "cgay@opendylan.org",
                       administrator?: #t,
                       activated?: #t)
end function init-admin-user;


define test test-initalize-storage ()
  let storage = make-storage();
  check-no-condition("initialize storage", initialize-storage(storage));
  check-no-condition("reinitialize storage", initialize-storage(storage));
end;

define suite user-test-suite ()
  test test-save/load-user;
  test test-remove-user;
end;

define test test-save/load-user ()
  let storage = init-storage();

  check-true("No users in database at startup",
             begin
               let users = load-all(storage, <wiki-user>);
               users.size = 1
               & users[0] = *admin-user*
             end);

  let old-user = make(<wiki-user>,
                      name: "wuser",
                      real-name: "Wiki User",
                      password: "password",
                      email: "luser@opendylan.org",
                      administrator?: #f,
                      activation-key: "abc",
                      activated?: #t);
  let author = old-user;
  check-no-condition("store user works",
                     store(storage, old-user, author, "comment"));

  let users = load-all(storage, <wiki-user>);
  check-equal("one user in db", 2, users.size);

  // Verify that all slots are the same in old-user and new-user.
  let new-user = find-element(users, method (u)
                                       u.user-name = old-user.user-name
                                     end);
  for (fn in list(user-name,
                  user-real-name,
                  user-password,
                  user-email,
                  administrator?,
                  user-activation-key,
                  user-activated?))
    check-equal(format-to-string("%s equal?", fn),
                fn(old-user),
                fn(new-user))
  end;
end test test-save/load-user;

/// Verify that when a user is deleted, any groups they belong to
/// are updated and any pages they own become owned by the admin user.
define test test-remove-user ()
end;


define suite page-test-suite ()
  test test-save/load-page;
  test test-remove-page;
end;

define test test-save/load-page ()
  let storage = init-storage();
  let old-page = make(<wiki-page>,
                      title: "Title",
                      content: "Content",
                      comment: "Comment",
                      owner: *admin-user*,
                      author: *admin-user*,
                      tags: #("tag"),
                      access-controls: $default-access-controls);
  store(storage, old-page, old-page.page-author, old-page.page-comment);
  let new-page = load(storage, <wiki-page>, old-page.page-title);
  for (fn in list(page-title,
                  page-content,
                  page-comment,
                  page-owner,
                  page-author,
                  page-tags))
    check-equal(format-to-string("%s equal?", fn),
                fn(old-page),
                fn(new-page));
  end;

  check-equal("revision is set to a git hash",
              40,
              new-page.page-revision.size);

  for (i from 1,
       fn in list(view-content-rules,
                  modify-content-rules,
                  modify-acls-rules))
    let old-rules = fn(old-page.page-access-controls);
    let new-rules = fn(new-page.page-access-controls);
    check-equal(format-to-string("#%d same number of rules", i),
                old-rules.size,
                new-rules.size);
    for (old-rule in old-rules,
         new-rule in new-rules)
      check-equal(format-to-string("#%d rule actions the same", i),
                  old-rule.rule-action,
                  new-rule.rule-action);
      check-equal(format-to-string("#%d rule targets the same", i),
                  old-rule.rule-target,
                  new-rule.rule-target);
    end for;
  end for;
end test test-save/load-page;

define test test-remove-page ()
end;


define suite group-test-suite ()
  test test-save/load-group;
  test test-remove-group;
end;

define test test-save/load-group ()
end;

define test test-remove-group ()
end;

/// Verify that when pages are created references to other pages are
/// updated correctly.
define test test-page-references ()
end;

define suite storage-test-suite ()
  test test-initalize-storage;
  suite user-test-suite;
  suite page-test-suite;
  suite group-test-suite;
  test test-page-references;
end suite storage-test-suite;

