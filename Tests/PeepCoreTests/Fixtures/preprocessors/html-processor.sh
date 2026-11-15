#!/bin/sh
# A custom processor (#106): the Markdown body, escaped, in a <pre>, after a fixed fragment with
# headings and markup the sanitizer must remove.
printf '<h1>Processed Title</h1>\n'
printf '<h2 id="own-id">Own Id</h2>\n'
printf '<p class="lead peep-find markdown-body" onclick="x()" style="color:red">Text <script>alert(1)</script></p>\n'
printf '<pre class="body">'
sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
printf '</pre>\n'
