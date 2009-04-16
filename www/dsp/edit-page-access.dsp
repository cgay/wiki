<%dsp:taglib name="wiki"/>
<%dsp:include url="xhtml-start.dsp"/>
<head>
   <title>Dylan: <wiki:show-page-title/></title>
  <%dsp:include url="meta.dsp"/>
</head>
<body>
  <%dsp:include url="header.dsp"/>
  <div id="content">
    <%dsp:include url="navigation.dsp"/>
    <%dsp:include url="options-menu.dsp"/>
    <div id="body">               
      <h2>Access to <a href="<wiki:show-page-permanent-link/>"><wiki:show-page-title/></a></h2>
      <form action="" method="post">
        <fieldset>
          <ol>
            <li id="editors-all-item">
              <input id="editors-all-input" type="radio" name="editing" value="all"/>
	      <label id="editors-all-label" for="editors-all-input">All</label>
            </li>
            <li id="editors-only-item">
              <input id="editors-only-input" type="radio" name="editing" value="only"/>
	      <label id="editors-only-label" for="editors-only-input">Only</label>
	      <fieldset>
	        <ol>
		  <li>
                    <select id="editors-list" name="editors" multiple="multiple">
                      <option>Foo</option>
                      <option>Bar</option>
                    </select>
	          </li>
                </ol>
              </fieldset>
            </li>
            <li id="comment-item">
              <label id="comment-label" for="comment-input">Comment:</label>
              <input id="comment-input" type="text" name="comment" value=""/>
            </li>
          </ol>
        </fieldset>
        <input type="submit" value="Save" />
      </form>
    </div>
  </div>
  <%dsp:include url="footer.dsp"/>
</body>
</html>