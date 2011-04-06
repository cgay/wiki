Module: wiki-test-suite
Author: Carl Gay


define suite wiki-test-suite ()
  suite storage-test-suite;
  suite acls-test-suite;
end;

define method main () => ()
  let filename = locator-name(as(<file-locator>, application-name()));
  if (split(filename, ".")[0] = "wiki-test-suite")
    // Minimize the logging verbosity
    $log.log-formatter := make(<log-formatter>,
                               pattern: "%{date:%H:%M:%S.%F} %-5L [%t] %m");

    // Run the tests
    run-test-application(wiki-test-suite);
  end;
end method main;

begin
  main()
end;
