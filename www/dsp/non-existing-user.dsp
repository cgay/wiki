<%dsp:include url="xhtml-start.dsp"/>
<%dsp:taglib name="wiki"/>
<head>
  <title>Dylan Wiki: <wiki:show-user-username/></title>
  <%dsp:include url="meta.dsp"/>
</head>
<body>
  <%dsp:include url="header.dsp"/>
  <div id="midsection">
    <div id="navigation">
      <wiki:include-page title="Wiki Left Nav"/>
    </div>
    <div id="content">
      <h2><wiki:show-user-username/></h2>

      <dsp:show-page-errors/>
      <dsp:show-page-notes/>

      <p class="hint">
        This user doesn't exist.
        <a href="<wiki:base/>/register">Register</a> or
        <a href="<wiki:base/>/login?redirect=<wiki:current/>">login</a>
        to create it.
      </p>
    </div>
  </div>
  <%dsp:include url="footer.dsp"/>
</body>
</html>
