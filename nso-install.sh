#!/bin/bash

NSO_BINARY_REPO_URL="https://earth.tail-f.com:8443"
REPO_URL_SORT='?C=M;O=D' # \ escapes for the script
NSO_INSTALL_DIR="(missing)"
REPO_USERNAME="(missing)"
NSO_VERSION="(missing)"

NSO_INSTALLED=false
NEDS=()

print_help () {
	echo "Script to download and install the latest NSO version and related NEDs

Usage: nso-install -v NSO-VERSION -d NSO-INSTALL-BASE-DIR [-r NSO-BINARY-REPO-URL] -u USERNAME [-p PASSWORD] [-n NED-NAME]*
Support OS versions: MACOS, CentOS

This script will attempt to install the NSO version indicated with the local-install option
in the directory NSO-INSTALL-BASE-DIR/NSO-VERSION
and the latest NEDs for the version of NSO specified.  You can specify 
multiple NEDs with the -n option.  Note this does not overwrite the NSO
installer NEDs but instead places them in a seperate location.  Based on the operating system
it will also attempt to install or update relevent packages that NSO relies on.

If the version of NSO is already installed or the latest version of the NED is already
present then no action is taken.  This can be run multiple times and only new items will
be downloaded and installed.

If you have a password with special characters such as pass!word escape
the special characters, ie. -p pass\!word when running the script
	"
	exit 0
}

print_error () {
	echo "ERROR: $1"
	if [ "$2" == "show_help" ]; then
		print_help
	fi
	exit 1
}

read_dom () {
    local IFS=\>
    read -d \< ENTITY CONTENT
    local ret=$?
    TAG_NAME=${ENTITY%% *}
    ATTRIBUTES=${ENTITY#* }
    return $ret
}

while getopts ":d:r:u:p:v:n:h" opt; do
	case $opt in
		d) NSO_INSTALL_DIR="$OPTARG"
		;;
		r) NSO_BINARY_REPO_URL="$OPTARG"
		;;
		u) REPO_USERNAME="$OPTARG"
		;;
		p) REPO_PASSWORD="$OPTARG"
		;;
		v) NSO_VERSION="$OPTARG"
		;;
		n) NEDS=("${NEDS[@]}" "$OPTARG") 
		;;
		h) print_help 
		;;
		\?) 
			print_error "Invalid option -$OPTARG" "show_help"
		;;
	esac
done

if [ -z "$REPO_PASSWORD" ]; then
	echo "Please enter the NSO binary server host password"
	while IFS= read -r -s -n1 pass; do
		if [[ -z $pass ]]; then
			echo
			break
		else
			echo -n '*'
			REPO_PASSWORD+=$pass
		fi
	done
fi

PASSWORD_ECHO="(hidden)"
if [ -z "$REPO_PASSWORD" ];
	then PASSWORD_ECHO="(missing)"
fi

LINUX_VERSION="$( uname | tr '[:upper:]' '[:lower:]' )"
NSO_BINARY="nso-$NSO_VERSION.$LINUX_VERSION.x86_64.installer.bin"
NSO_NED_REPOSITORY="$NSO_INSTALL_DIR/neds"
LOCAL_BINARYS_DIR="$NSO_INSTALL_DIR/binaries"

printf "Linux version: %s\n" "$LINUX_VERSION"
printf "NSO version: %s\n" "$NSO_VERSION"
printf "NSO Install Location: %s\n" "$NSO_INSTALL_DIR/$NSO_VERSION"
printf "NED Install Location: %s\n" "$NSO_NED_REPOSITORY/$NSO_VERSION"
printf "Binary Repo username: %s\n" "$REPO_USERNAME"
printf "Binary Repo password: %s\n" "$PASSWORD_ECHO"
printf "NEDs: %s\n" ""${NEDS[@]}""

if [ -z "$REPO_PASSWORD" ] || [ "$REPO_USERNAME" == "(missing)" ] || [ -z "$NSO_VERSION" ] || [ "$NSO_INSTALL_DIR" == "(missing)" ]; then
	print_error "Please enter missing information" show_help
fi

echo "Checking if version ($NSO_BINARY) is available on repo server"
nso_binary_url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs/$NSO_BINARY"
if ! curl --silent --output /dev/null --head --fail $nso_binary_url; then
	print_error "Version is not valid on repo, File does not exist: $NSO_BINARY_REPO_URL/ncs/$NSO_BINARY"
fi

if [ ! -d $NSO_INSTALL_DIR ]; then 
	echo "Creating $NSO_INSTALL_DIR"
	mkdir $NSO_INSTALL_DIR
else
	if [ -e $NSO_INSTALL_DIR/$NSO_VERSION/VERSION ]; then
		echo "NSO version $NSO_VERSION already installed"
		NSO_INSTALLED=true
	fi
fi
if [ ! -d $LOCAL_BINARYS_DIR ]; then 
	echo "Creating $LOCAL_BINARYS_DIR"
	mkdir $LOCAL_BINARYS_DIR
fi
if [ ! -d $NSO_NED_REPOSITORY ]; then 
	echo "Creating $NSO_NED_REPOSITORY"
	mkdir $NSO_NED_REPOSITORY
fi
if [ ! -d $NSO_NED_REPOSITORY/$NSO_VERSION ]; then 
	echo "Creating $NSO_NED_REPOSITORY/$NSO_VERSION"
	mkdir $NSO_NED_REPOSITORY/$NSO_VERSION
fi


if [ "$NSO_INSTALLED" !=  "true" ]; then
	if [ ! -e $LOCAL_BINARYS_DIR/$NSO_BINARY ]; then
		echo "NSO Binary file does not exist locally, downloading..."
		curl $nso_binary_url  >> $LOCAL_BINARYS_DIR/$NSO_BINARY
		chmod a+x $LOCAL_BINARYS_DIR/$NSO_BINARY
	else
		echo "NSO Binary file exist"
	fi
	echo "Performing NSO Local install to $NSO_INSTALL_DIR/$NSO_VERSION"
	$LOCAL_BINARYS_DIR/$NSO_BINARY --local-install $NSO_INSTALL_DIR/$NSO_VERSION
fi

for ned in "${NEDS[@]}"; do
	NED_DOWNLOAD_FILE=""
	echo "Checking if $ned NED is available on Repo server"
	url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs-pkgs/$ned"
#	echo $url
	if ! curl --output /dev/null --silent --head --fail $url; then
		echo "** WARNING **: NED $ned at location ($NSO_BINARY_REPO_URL/ncs-pkgs/$ned) does not exist on repo server"
		echo "Skipping this NED"
	else
		echo "NED exists - $ned: Retrieving lastest filename"
		file_list_xml=$(curl --silent $url/$NSO_VERSION/"$REPO_URL_SORT")
#		echo $file_list_xml
		while read_dom; do
			if [[ $ENTITY == *"$ned"*"bin"* ]]; then
				NED_DOWNLOAD_FILE=$CONTENT
				echo "NED - $ned binary: $NED_DOWNLOAD_FILE"
				break
			fi
			if [[ $ENTITY == *"$ned"*"tar.gz"* ]] && [[ $ENTITY != *".sha"* ]]; then
				NED_DOWNLOAD_FILE=$CONTENT
				echo "NED - $ned file: $NED_DOWNLOAD_FILE"
				break
			fi
		done < <(echo "$file_list_xml")
		NED_FILE_VERSION="${NED_DOWNLOAD_FILE/.tar.gz/}"
		NED_FILE_VERSION="${NED_FILE_VERSION/.signed.bin/}"
		echo "NED base filename: $NED_FILE_VERSION"
		if [ -e $NSO_NED_REPOSITORY/$NSO_VERSION/$NED_FILE_VERSION.tar.gz ]; then
			echo "NED $ned ($NED_FILE_VERSION) for NSO version $NSO_VERSION already installed in $NSO_NED_REPOSITORY/$NSO_VERSION"
		else
			url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs-pkgs/$ned/$NSO_VERSION/$NED_DOWNLOAD_FILE"
			if [[ $NED_DOWNLOAD_FILE == *"$ned"*"tar.gz"* ]]; then
				echo "Downloading NED $ned for NSO version $NSO_VERSION to $NSO_NED_REPOSITORY/$NSO_VERSION"
				curl $url >> $NSO_NED_REPOSITORY/$NSO_VERSION/$NED_DOWNLOAD_FILE
			else
				if [ -e $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE ]; then
					echo "NED binary for $ned ($NED_FILE_VERSION) for NSO version $NSO_VERSION already downloaded"
				else
					echo "NED Binary file ($NED_DOWNLOAD_FILE) does not exist, downloading..."
					curl $url  >> $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE
					chmod a+x $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE
				fi
				if [ -d $NSO_INSTALL_DIR/temp ]; then 
					rm -rf $NSO_INSTALL_DIR/temp
				fi
				echo "Unpacking NED to $NSO_INSTALL_DIR"/temp
				mkdir $NSO_INSTALL_DIR/temp
				cp $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE $NSO_INSTALL_DIR/temp/$NED_DOWNLOAD_FILE
				( cd $NSO_INSTALL_DIR/temp; eval ./$NED_DOWNLOAD_FILE; echo "Copying NED ($NED_FILE_VERSION.tar.gz) to $NSO_NED_REPOSITORY/$NSO_VERSION"; cp $NSO_INSTALL_DIR/temp/$NED_FILE_VERSION.tar.gz $NSO_NED_REPOSITORY/$NSO_VERSION )
				rm -rf $NSO_INSTALL_DIR/temp
			fi
		fi
	fi
done

echo "Install Complete"

