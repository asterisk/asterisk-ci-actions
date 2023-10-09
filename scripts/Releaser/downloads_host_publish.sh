#!/bin/bash

# Bail on any error
set -e -B

# deploy failsafe

declare needs=( end_tag )
declare wants=( dst_dir product )
declare tests=( dst_dir )

progdir="$(dirname $(realpath $0) )"
source "${progdir}/common.sh"

: ${DST_DIR:=/home/${PRODUCT}-build}


declare -A end_tag_array
tag_parser ${END_TAG} end_tag_array || bail "Unable to parse end tag '${END_TAG}'"
${DEBUG} && declare -p end_tag_array

# Set up what to fetch from github

if ${end_tag_array[no_patches]} ; then
	patterns1="{${end_tag_array[artifact_prefix]}-${END_TAG}.{md5,sha1,sha256,tar.gz,tar.gz.asc},{ChangeLog,README}-${END_TAG}.md}"
else
	patterns1="{${end_tag_array[artifact_prefix]}-${END_TAG}{.{md5,sha1,sha256,tar.gz,tar.gz.asc},-patch.{md5,sha1,sha256,tar.gz,tar.gz.asc}},{ChangeLog,README}-${END_TAG}.md}"
fi

files=$(eval echo $patterns1)
urls=$(eval echo "https://github.com/asterisk/${PRODUCT}/releases/download/${END_TAG}/$patterns1")
echo ------------
echo $files
echo ------------
echo $urls
echo ------------



cd $DST_DIR
mkdir -p telephony/${end_tag_array[download_dir]}/pending
cd telephony/${end_tag_array[download_dir]}/pending

# Fetch the files and fail if any can't be downloaded.
curl --no-progress-meter --fail-early -f -L --remote-name-all $urls

# If we do get them all, move them into the releases directory.
rsync -vaH --remove-source-files * ../releases/

# Remove any existing RC links (including the transient -testing link)
cd ..

rm -f *${end_tag_array[major]}.${end_tag_array[minor]}${end_tag_array[patchsep]}${end_tag_array[patch]}-rc*
rm -f *-testing*

if [ ${end_tag_array[release_type]} == "rc" ] ; then
	# Create the direct links
	cd releases
	ln -sfr $files ../
	echo 'Release candidate so not disturbing existing production links'
	from=.${end_tag_array[minor]}${end_tag_array[patchsep]}${end_tag_array[patch]}
	# Also create a transient permalink (for each major version) to the release candidate
	to=-testing
	for f in $files ; do
		ln -sfr $f ../${f/${from}/${to}}
	done
	exit 0
fi

# GA release

# Remove previous links
rm -f {${PRODUCT},ChangeLog,README}-${tagarray[certprefix]}${end_tag_array[major]}.*

# Create the direct links
cd releases
ln -sfr $files ../

# Create the -current links
if ${end_tag_array[certified]} ; then
   	from=${end_tag_array[major]}.${end_tag_array[minor]}${end_tag_array[patchsep]}${end_tag_array[patch]}
   	to=current
else
   	from=.${end_tag_array[minor]}${end_tag_array[patchsep]}${end_tag_array[patch]}
   	to=-current
fi

for f in $files ; do
   	ln -sfr $f ../${f/${from}/${to}}
done
