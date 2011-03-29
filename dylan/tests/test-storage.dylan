Module: wiki-test-suite
Synopsis: Tests of the storage protocol

// This should be the only function here that depends on the git back-end.
// TODO: make paths configurable
define function make-storage
    () => (storage :: <storage>)
  let pathname = "c:/tmp/test-wiki-storage";
  if (file-exists?(pathname))
    delete-directory(pathname);
  end;
  make(<git-storage>,
       repository-root: pathname,
       executable: "c:\\Program Files\\Git\\bin\\git.exe",
       branch: "master")
end;

define function init-storage
    () => (storage :: <storage>)
  let storage = make-storage();
  initialize-storage(storage);
  storage
end;
       

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
  let username = "test";

  check-condition("non-existant user gets error",
                  <storage-error>,
                  load(storage, <wiki-user>, username));

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
                     store(storage, old-user, author, username));
  let new-user = load(storage, <wiki-user>, username);
  check-equal("name",     old-user.user-name,           new-user.user-name);
  check-equal("real-name", old-user.user-real-name,     new-user.user-real-name);
  check-equal("passward", old-user.user-password,       new-user.user-password);
  check-equal("email",    old-user.user-email,          new-user.user-email);
  check-equal("admin?",   old-user.administrator?,      new-user.administrator?);
  check-equal("actkey",   old-user.user-activation-key, new-user.user-activation-key);
  check-equal("active?",  old-user.user-activated?,     new-user.user-activated?);
end test test-save/load-user;

/// Verify that when a user is deleted, any groups they belong to
/// are updated and any pages they own become owned by the admin user.
define test test-remove-user ()
end;

define suite page-test-suite ()
  test test-save/load-user;
  test test-remove-page;
end;

define test test-save/load-page ()
end;

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

