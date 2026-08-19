#!/bin/bash
CHECK_DIR=$(dirname $(realpath $0))

cat <<-EOF >/tmp/dump_checklists.sh
#!/bin/bash
PR_CHECKLIST_PATH=/dev/stderr
source ${CHECK_DIR}/checks.functions
EOF

for f in $(find "${CHECK_DIR}" -name '[0-9]*.sh' | sort) ; do
	check_name=$(basename -s .sh $f)
	{
		echo "export CHECK_NAME=${check_name:3}" >>/tmp/dump_checklists.sh
		echo "echo" >>/tmp/dump_checklists.sh
		sed -n -r -e '/<<[-]?EOF.*print_checklist_item/,/^\s*EOF$/!d' -e 's/^\s*//gp' $f | \
			sed -r -e 's/>>.*//g'
	} >>/tmp/dump_checklists.sh
done
chmod a+x /tmp/dump_checklists.sh
/tmp/dump_checklists.sh
