#!/usr/bin/bash

set -x

ulimit -a

sysctl kernel.core_pattern

cat <<EOF > ~/.pgpass
*:*:*:postgres:postgres
*:*:*:asterisk:asterisk
EOF

chmod go-rwx ~/.pgpass
sudo -u postgres createuser -h postgres -w --username=postgres -RDIElS asterisk
sudo -u postgres createdb -h postgres -w --username=postgres -E UTF-8 -O asterisk asterisk
sudo -u postgres psql -h postgres -w -l

exit 0
