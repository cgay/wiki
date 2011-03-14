Module: wiki-test-suite
Synopsis: Tests of the storage protocol

// This should be the only function here that depends on the git back-end.
// TODO: make paths configurable
define function make-storage
    () => (storage :: <storage>)
  let pathname = "c:/tmp/test-wiki-storage";
  remove-directory(pathname);
  make(<git-storage>,
       repository-root: pathname,
       executable: "c:/program files/git/bin/git.exe",
       branch: "master")
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
end;

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

