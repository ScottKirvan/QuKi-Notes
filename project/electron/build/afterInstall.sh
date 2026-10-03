#!/bin/sh
# Installs /usr/bin/quki and /usr/bin/quki-mcp wrapper scripts that invoke the
# bundled CLI and MCP server through the app's own Electron binary with
# ELECTRON_RUN_AS_NODE=1.
#
# electron-builder installs to /opt/<productName>/ — for "QuKi Notes" this is
# /opt/QuKi Notes/ (note the space). The executable is named after the package
# name field in package.json: "quki-notes".
cat > /usr/bin/quki << 'WRAPPER_EOF'
#!/bin/sh
ELECTRON_RUN_AS_NODE=1 "/opt/QuKi Notes/quki-notes" "/opt/QuKi Notes/resources/cli/main.mjs" "$@"
WRAPPER_EOF
chmod +x /usr/bin/quki

cat > /usr/bin/quki-mcp << 'WRAPPER_EOF'
#!/bin/sh
ELECTRON_RUN_AS_NODE=1 "/opt/QuKi Notes/quki-notes" "/opt/QuKi Notes/resources/mcp/server.mjs" "$@"
WRAPPER_EOF
chmod +x /usr/bin/quki-mcp
