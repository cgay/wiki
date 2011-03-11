wiki
====

This library is a wiki written in the Dylan language.  It supports the
following features:

  * All data is stored in a git repository so it can be edited offline
    if desired, backed up, reverted, etc.

  * Account verification.

  * Access controls -- each object in the wiki can be restricted to
    being viewed or edited by specific sets of users.

How to Run
==========

Build the library and then run it like this::

   wiki --config config.xml


You will need to tweak these values in the config file:

* *koala.wiki.repository* -- Make it point to the root directory of
   your wiki git repository.  Example::

     $ cd
     $ mkdir wiki-data
     $ cd wiki-data
     $ git init

     <wiki repository = "/home/you/wiki-data" ...>

* If the "git" executable is not on the path of the user running the
  wiki, then you need to specify it in the <wiki> element::

     <wiki git-executable = "/usr/bin/git" ... />

* *koala.wiki.static-directory* -- Make it point at the "www" subdirectory
  (I guess this should be made relative to <server-root>.)

* *koala.wiki.administrator.password* -- Choose a password you like.
  Feel free to rename the administrator account to whatever you like.



Data File Layout
================

The wiki data is stored in a git repository.  The files are laid out
as follows::

  <repo-root>/
    domains
      <domain-1>/
	<page-name-1>/content  # page markup
	<page-name-1>/tags     # page tags, one per line
	<page-name-1>/acls     # page ACLs, one per line
	<page-name-2>/content
	<page-name-2>/tags
	<page-name-2>/acls
	...
      <domain-2>/
	<page-name-1>/content
	<page-name-1>/tags
	<page-name-1>/acls
	...
    
The default domain name is "main" and currently there is no way to
create new domains.
