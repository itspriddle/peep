#!/bin/sh
# A custom processor (#106) for UI tests: ignores the Markdown and writes a fixed fragment,
# including a script the sanitizer must remove.
cat > /dev/null
printf '<h1>Processor fixture</h1>\n<p class="processed">Rendered by the processor.</p>\n'
printf '<script>document.body.textContent = "pwned"</script>\n'
