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



Data File Layout
================

All wiki data except for user accounts are stored in a git repository.
The files are laid out as follows::

  <repo-root>/
    groups
    sandboxes
      <sandbox-1>/
        <page-name-1>/content  # page markup
        <page-name-1>/tags     # page tags, one per line
        <page-name-1>/acls     # page ACLs, one per line
        <page-name-2>/content
        <page-name-2>/tags
        <page-name-2>/acls
        ...
      <sandbox-2>/
        <page-name-1>/content
        <page-name-1>/tags
        <page-name-1>/acls
        ...
    
The default sandbox name is "main" and currently there is no way to
create new sandboxes.  In some other wikis these would be called
"wikis".  The format of each file is described below.

content
    The ``content`` file contains the raw wiki page markup text and
    nothing else.

tags
    The ``tags`` file contains one tag per line and nothing else.  Tags may
    contain whitespace.

acls
    The ``acls`` file has the following format::

        owner: <username>
        view-content: <rule>,<rule>,...
        modify-content: <rule>,<rule>,...
        modify-acls: <rule>,<rule>,...

    Rules are defined by the following pseudo BNF::

        <rule>   ::= <access>@<name>
	<access> ::= allow | deny
	<name>   ::= <user> | <group> | $any | $trust | $owner
	<user>   ::= any user name
	<group>  ::= any group name

    The special name "$any" means any user, "$trusted" means logged in users
    and "$owner" means the page owner.  "$" is not allowed in user or group
    names so there is no conflict.

groups
    name:owner:member1:member2:...
    <n-bytes>
    ...description in n bytes...



users
    name1:admin?:password:email:creation-date:activation-key:active?
    name2:...
    ...

    Password is stored in base-64 for now, to be slightly better than
    clear text.  This must be improved.  Email is also in base-64.
