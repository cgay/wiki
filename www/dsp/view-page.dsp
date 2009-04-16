<%dsp:taglib name="wiki"/>
<%dsp:include url="xhtml-start.dsp"/>
<head>
  <title>Dylan: <wiki:show-page-title/>
    <dsp:unless test="latest-page-version?">
      @ #<wiki:show-version-number/>
    </dsp:unless>
  </title>
  <%dsp:include url="meta.dsp"/>
</head>
<body>
  <%dsp:include url="header.dsp"/>
  <div id="content">
    <%dsp:include url="navigation.dsp"/>
    <%dsp:include url="options-menu.dsp"/>
    <div id="body">
      <h2><wiki:show-page-title/>
          <dsp:unless test="latest-page-version?">
	    <em>@ #<wiki:show-version-number/></em>
          </dsp:unless>
      </h2>
      <wiki:show-page-content content-format="xhtml"/>
    </div>
  </div>
  <%dsp:include url="footer.dsp"/>
</body>
</html>