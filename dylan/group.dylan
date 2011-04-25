Module: %wiki
Synopsis: Group maintenance


// todo -- I don't like that these are mutable.  It makes it hard to
//         reason about the code.  Probably goes for other objects too.
//
define class <wiki-group> (<wiki-object>)
  slot group-name :: <string>,
    required-init-keyword: name:;
  slot group-owner :: <wiki-user>,
    required-init-keyword: owner:;
  slot group-members :: <stretchy-vector> = make(<stretchy-vector>),
    init-keyword: members:;
  slot group-description :: <string> = "",
    init-keyword: description:;
end class <wiki-group>;

define method make
    (class == <wiki-group>, #rest args, #key members :: <sequence> = #[])
 => (group :: <wiki-group>)
  apply(next-method, class, members: as(<stretchy-vector>, members), args)
end;

define method initialize
    (group :: <wiki-group>, #key)
  add-new!(group.group-members, group.group-owner);
end;

// This is pretty restrictive for now.  Easier to loosen the rules later
// than to tighten them up.  The name has been pre-trimmed and %-decoded.
//
define method validate-group-name
    (name :: <string>) => (name :: <string>)
  if (empty?(name))
    error("Group is required.");
  elseif (~regex-search(compile-regex("^[A-Za-z0-9_-]+$"), name))
    error("Group names may contain only alphanumerics, hyphens and underscores.");
  end;
  name
end method validate-group-name;

// Must come up with a simpler, more general way to handle form errors...
define wf/error-test (name) in wiki end;



define method permanent-link
    (group :: <wiki-group>)
 => (url :: <url>)
  group-permanent-link(group)
end;

define method group-permanent-link
    (group :: <wiki-group>)
 => (url :: <url>)
  let location = wiki-url("/group/view/%s", group.group-name);
  transform-uris(request-url(current-request()), location, as: <url>)
end;

define method redirect-to (group :: <wiki-group>)
  redirect-to(permanent-link(group));
end;


// methods

define method find-group
    (name :: <string>)
 => (group :: false-or(<wiki-group>))
  element(*groups*, as-lowercase(name), default: #f)
end;

// Find all groups that a user is a member of.
//
define method user-groups
    (user :: <wiki-user>)
 => (groups :: <collection>)
  choose(method (group)
           member?(user, group.group-members)
         end,
         value-sequence(*groups*))
end;

define method groups-owned-by-user
    (user :: <wiki-user>)
 => (groups :: <collection>)
  choose(method (group)
           group.group-owner = user
         end,
         value-sequence(*groups*))
end;

define method rename-group
    (name :: <string>, new-name :: <string>,
     #key comment :: <string> = "")
 => ()
  let group = find-group(name);
  if (group)
    rename-group(group, new-name, comment: comment)
  end if;
end;

define method rename-group
    (group :: <wiki-group>, new-name :: <string>,
     #key comment :: <string> = "")
 => ()
  let old-lc-name = as-lowercase(group.group-name);
  let new-lc-name = as-lowercase(new-name);
  if (old-lc-name ~= new-lc-name)
    if (find-group(new-lc-name))
      // todo -- raise more specific error...test...
      error("group %s already exists", new-name);
    end;
    let comment = concatenate("was: ", group.group-name, ". ", comment);
    with-lock ($group-lock)
      remove-key!(*groups*, old-lc-name);
      group.group-name := new-name;
      *groups*[new-lc-name] := group;
    end;
    store(*storage*, group, authenticated-user(), comment,
          standard-meta-data(group, "rename"));
  end if;
end method rename-group;

define method create-group
    (name :: <string>, #key comment :: <string> = "")
 => (group :: <wiki-group>)
  let author = authenticated-user();
  let group = make(<wiki-group>,
                   name: name,
                   owner: author);
  store(*storage*, group, author, comment, standard-meta-data(group, "create"));
  with-lock ($group-lock)
    *groups*[as-lowercase(name)] := group;
  end;
  group
end method create-group;

define method add-member
    (user :: <wiki-user>, group :: <wiki-group>,
     #key comment :: <string> = "")
 => ()
  add-new!(group.group-members, user);
  let comment = concatenate("added ", user.user-name, ". ", comment);
  store(*storage*, group, authenticated-user(), comment,
        standard-meta-data(group, "add-members"));
end;

define method remove-member
    (user :: <wiki-user>, group :: <wiki-group>,
     #key comment :: <string> = "")
 => ()
  remove!(group.group-members, user);
  let comment = concatenate("removed ", user.user-name, ". ", comment);
  store(*storage*, group, authenticated-user(), comment,
        standard-meta-data(group, "remove-members"));
end;

define method remove-group
    (group :: <wiki-group>, comment :: <string>)
 => ()
  delete(*storage*, group, authenticated-user(), comment,
         standard-meta-data(group, "delete"));
  with-lock ($page-lock)
    for (page in *pages*)
      remove-rules-for-target(page.page-access-controls, group);
    end;
  end;
  with-lock ($group-lock)
    remove-key!(*groups*, as-lowercase(group.group-name));
  end;
end method remove-group;


//// List Groups (note not a subclass of <group-page>)

define class <list-groups-page> (<wiki-dsp>)
end;

define method respond-to-get
    (page :: <list-groups-page>, #key)
  local method group-info (group)
          let len = group.group-members.size;
          make-table(<string-table>,
                     "name" => group.group-name,
                     "count" => integer-to-string(len),
                     "s" => iff(len = 1, "", "s"),
                     "description" => quote-html(group.group-description))
        end;
  set-attribute(page-context(), "all-groups",
                map(group-info, with-lock ($group-lock)
                                  value-sequence(*groups*)
                                end));
  next-method();
end method respond-to-get;

// Posting to /group/list creates a new group.
//
define method respond-to-post
    (page :: <list-groups-page>, #key)
  let user = authenticated-user();
  let (new-name, error?) = validate-form-field("group", validate-group-name);
  if (~error? & find-group(new-name))
    add-field-error("group", "A group named %s already exists.", new-name);
  end;
  if (page-has-errors?())
    respond-to-get(*list-groups-page*)
  else
    redirect-to(create-group(new-name));
  end;
end method respond-to-post;


//// Group page

define class <group-page> (<wiki-dsp>)
end;

// Add basic group attributes to page context and display the page template.
//
define method respond-to-get
    (page :: <group-page>, #key name :: <string>)
  let name = percent-decode(name);
  let group = find-group(name);
  let pc = page-context();
  set-attribute(pc, "group-name", name);
  let user = authenticated-user();
  if (user)
    set-attribute(pc, "active-user", user.user-name);
  end;
  if (group)
    set-attribute(pc, "group-owner", group.group-owner.user-name);
    set-attribute(pc, "group-description", group.group-description);
    set-attribute(pc, "group-members", sort(map(user-name, group.group-members)));
    next-method();
  else
    // Should only get here via a typed-in URL.
    respond-to-get(*non-existing-group-page*);
  end if;
end method respond-to-get;


//// Edit Group

define class <edit-group-page> (<group-page>)
end;

define method respond-to-post
    (page :: <edit-group-page>, #key name)
  let name = trim(percent-decode(name));
  let group = find-group(name);
  if (~group)
    // foreign post?
    respond-to-get(*non-existing-group-page*);
  else
    let new-name = validate-form-field("group-name", validate-group-name);
    let owner-name = validate-form-field("group-owner", validate-user-name);
    let new-owner = find-user(owner-name);
    let comment = trim(get-query-value("comment") | "");
    let description = trim(get-query-value("group-description") | "");
    if (empty?(description))
      add-field-error("group-description", "A description is required.");
    end;
    if (~new-owner)
      add-field-error("group-owner", "User %s unknown", owner-name);
    end;
    if (new-name ~= name & find-group(new-name))
      add-field-error("group-name",
                      "A group named %s already exists.", new-name);
    end;
    if (page-has-errors?())
      // redisplay page with errors
      respond-to-get(*edit-group-page*, name: name);
    else
      // todo -- the rename and save should be part of a transaction.
      if (new-name ~= name)
        rename-group(group, new-name, comment: comment);
        name := new-name;
      end;
      if (description ~= group.group-description
            | new-owner ~= group.group-owner)
        group.group-description := description;
        group.group-owner := new-owner;
        store(*storage*, group, authenticated-user(), comment,
              standard-meta-data(group, "edit"));
      end;
      redirect-to(group);
    end if;
  end if;
end method respond-to-post;


//// Remove Group

define class <remove-group-page> (<group-page>)
end;

define method respond-to-post
    (page :: <remove-group-page>, #key name :: <string>)
  let group-name = percent-decode(name);
  let group = find-group(group-name);
  if (group)
    let author = authenticated-user();
    if (author & (author = group.group-owner | administrator?(author)))
      remove-group(group, get-query-value("comment") | "");
      add-page-note("Group %s removed", group-name);
    else
      add-page-error("You do not have permission to remove this group.")
    end;
    respond-to-get(*list-groups-page*);
  else
    respond-to-get(*non-existing-group-page*);
  end;
end method respond-to-post;


//// Edit Group Members

// TODO: It should be possible to edit the group name, owner,
//       and members all in one page.

define class <edit-group-members-page> (<edit-group-page>)
end;

define method respond-to-get
    (page :: <edit-group-members-page>,
     #key name :: <string>, must-exist :: <boolean> = #t)
  let name = percent-decode(name);
  let group = find-group(name);
  if (group)
    with-lock ($user-lock)
      // Note: user must be logged in.  That check is done in the template.
      // non-members is for the add/remove members page
      set-attribute(page-context(),
                    "non-members",
                    sort(key-sequence(*users*)));
      // Add all users to the page context so they can be selected
      // for group membership.
      set-attribute(page-context(),
                    "all-users",
                    sort(key-sequence(*users*)));
    end with-lock;
  end if;
  next-method();
end method respond-to-get;

define method respond-to-post
    (page :: <edit-group-members-page>, #key name :: <string>)
  let group-name = percent-decode(name);
  let group = find-group(group-name);
  if (group)
    with-query-values (add as add?, remove as remove?, users, members, comment)
      if (add? & users)
        if (instance?(users, <string>))
          users := list(users);
        end if;
        let users = choose(identity, map(find-user, users));
        do(rcurry(add-member, group, comment:, comment), users);
      elseif (remove? & members)
        if (instance?(members, <string>))
          members := list(members);
        end if;
        let members = choose(identity, map(find-user, members));
        do(rcurry(remove-member, group, comment:, comment), members);
      end if;
      respond-to-get(page, name: name);
    end;
  else
    respond-to-get(*non-existing-group-page*);
  end;
end method respond-to-post;


define named-method can-modify-group?
    (page :: <group-page>)
  let user = authenticated-user();
  user & (administrator?(user)
            | user.user-name = get-attribute(page-context(), "active-user"));
end;

