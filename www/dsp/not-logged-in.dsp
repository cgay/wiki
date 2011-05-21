<%dsp:include url="xhtml-start.dsp"/>
<%dsp:taglib name="wiki"/>
<head>
  <title>Dylan Wiki: Login</title>
  <%dsp:include url="meta.dsp"/>
</head>
<body>
  <%dsp:include url="header.dsp"/>
  <div id="content">
    <div id="navigation">
      <wiki:include-page title="Wiki Left Nav"/>
    </div>
    <%dsp:include url="options-menu.dsp"/>
    <div id="body">
      <h2>Error</h2>

      <dsp:show-page-errors/>
      <dsp:show-page-notes/>

      <p>You have to <a href="<wiki:base/>/login?redirect=<wiki:current/>">login</a> to go on.</p>
    </div>
  </div>
  <%dsp:include url="footer.dsp"/>
</body>
</html>
