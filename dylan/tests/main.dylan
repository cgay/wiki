Module: wiki-test-suite
Author: Carl Gay


define suite wiki-test-suite
    (setup-function: start-sockets)
  suite storage-test-suite;
  suite acls-test-suite;
end;

define method main () => ()
  let filename = locator-name(as(<file-locator>, application-name()));
  if (split(filename, ".")[0] = "wiki-test-suite")
    run-test-application(wiki-test-suite);
  end;
end method main;

begin
  main()
end;
