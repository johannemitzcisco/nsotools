#!/bin/bash

NSO_BINARY_REPO_URL="https://earth.tail-f.com:8443"
JAVA_RPM_URL='http://download.oracle.com/otn-pub/java/jdk/8u144-b01/090f390dda5b47b9b721c7dfaa008135/jdk-8u144-linux-x64.rpm'
JAVA_VERSION='jdk1.8.0_144'
REPO_URL_SORT='?C=M;O=D' # \ escapes for the script
NSO_INSTALL_DIR="(missing)"
REPO_USERNAME="(missing)"
NSO_VERSION="(missing)"
SKIP_OS=false
DISABLE_ENV_PROXY=false
NSO_INSTALLED=false
NEDS=()

print_help () {
	echo "
--------  HELP  ----------
Script to download and install the latest NSO version and related NEDs

Support OS versions to install on: MACOS, CentOS

Usage: nso-install -v NSO-VERSION -d NSO-INSTALL-BASE-DIR [OPTIONS]
OPTIONS
[-r NSO-BINARY-REPO-URL] - An http/https url where the software is located
[-u USERNAME] - Username for repo authentication
[-p PASSWORD] - Password for repo authentication
[-i PROXY] - proxy URL
[-x] - disable proxy environment variables 
[-s] - skip install and/or update of required OS packages
[-n NED-NAME]* - Multiple -n entries to specify the NEDs to download and unpack
[-h] - pring help

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

If you are having trouble downloading you may need to adjust your proxy environment
settings.
	"
	exit 0
}

print_msg () {
	printf "$1: %s\n" "$2"
}
print_error () {
	print_msg "ERROR" "$1"
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

while getopts ":d:r:u:p:v:n:sxh" opt; do
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
		s) SKIP_OS=true
		;;
		x) DISABLE_ENV_PROXY=true
		;;
		h) print_help 
		;;
		\?) 
			print_error "Invalid option -$OPTARG" "show_help"
		;;
	esac
done

if [ -z "$REPO_PASSWORD" ]; then
	print_msg "INFORMATION REQUIRED" "Please enter the NSO binary server host password"
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
DISTRO="unknown"
if [ "$LINUX_VERSION" == "linux" ]; then
    # If available, use LSB to identify distribution
    if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
        DISTRO_TEMP=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
    # Otherwise, use release info file
    else
        DISTRO_TEMP=$(ls -d /etc/[A-Za-z]*[_-][rv]e[lr]* | grep -v "lsb" | cut -d'/' -f3 | cut -d'-' -f1 | cut -d'_' -f1)
	if [[ $DISTRO_TEMP == *"centos"* ]]; then
		DISTRO="centos"
	fi
    fi
elif [ "$LINUX_VERSION" == "darwin" ]; then
	DISTRO="macos"
fi

echo "-----  Install Configuration -------------------"
printf "Linux version: %s\n" "$LINUX_VERSION"
printf "NSO version: %s\n" "$NSO_VERSION"
printf "NSO Install Location: %s\n" "$NSO_INSTALL_DIR/$NSO_VERSION"
printf "NED Install Location: %s\n" "$NSO_NED_REPOSITORY/$NSO_VERSION"
printf "Binary Repo username: %s\n" "$REPO_USERNAME"
printf "Binary Repo password: %s\n" "$PASSWORD_ECHO"
printf "NED: %s\n" ""${NEDS[@]}""
printf "Distribution Type: %s\n" "$DISTRO"
printf "Skip OS Update: %s\n" "$SKIP_OS"
printf "Disable Envronment Proxy Configuration: %s\n" "$DISABLE_ENV_PROXY"
echo ""

if [ -z "$REPO_PASSWORD" ] || [ "$REPO_USERNAME" == "(missing)" ] || [ -z "$NSO_VERSION" ] || [ "$NSO_INSTALL_DIR" == "(missing)" ]; then
	print_error "Please enter missing information" show_help
fi
if [ "$DISTRO" == 'unknown' ]; then
	print_error "$DISTO unsupported by this program.  Only centos and macos supported"
fi
if [ "$DISABLE_ENV_PROXY" == "true" ]; then
	_http_proxy=$http_proxy
	_https_proxy=$https_proxy
	_HTTP_PROXY=$HTTP_PROXY
	_HTTPs_PROXY=$HTTPS_PROXY
	unset http_proxy
	unset https_proxy
	unset HTTP_PROXY
	unset HTTPS_PROXY
fi

if [ "$SKIP_OS" == "true" ]; then
	print_msg "INFO" "Skipping OS update check"
elif [ "$DISTRO" == 'centos' ]; then
	yum update -y
	yum install -y ant perl wget net-tools zlib-dev openssl-devel sqlite-devel bzip2-devel python-devel
	yum -y groupinstall "Development tools"
	if [ ! -e /usr/java/$JAVA_VERSION/bin/java ]; then
		curl -v -j -k -L -H "Cookie: oraclelicense=accept-securebackup-cookie" -x http://proxy.esl.cisco.com:80 $JAVA_RPM_URL >> $LOCAL_BINARYS_DIR/$JAVA_VERSION-linux-x64.rpm
		rpm -ihv $LOCAL_BINARYS_DIR/$JAVA_VERSION-linux-x64.rpm
		/usr/sbin/alternatives --install /usr/bin/java java /usr/java/$JAVA_VERSION/bin/java
		/usr/sbin/alternatives --set java /usr/java/$JAVA_VERSION/jre/bin/java
	fi
	echo
fi

print_msg "INFO" "Checking if version ($NSO_BINARY) is available on repo server"
nso_binary_url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs/$NSO_BINARY"
if ! curl --silent --output /dev/null --head --fail $nso_binary_url; then
	print_error "Version is not valid on repo, File does not exist: $NSO_BINARY_REPO_URL/ncs/$NSO_BINARY"
fi

if [ ! -d $NSO_INSTALL_DIR ]; then 
	print_msg "INFO" "Creating $NSO_INSTALL_DIR"
	mkdir $NSO_INSTALL_DIR
else
	if [ -e $NSO_INSTALL_DIR/$NSO_VERSION/VERSION ]; then
		print_msg "INFO" "NSO version $NSO_VERSION already installed"
		NSO_INSTALLED=true
	fi
fi
if [ ! -d $LOCAL_BINARYS_DIR ]; then 
	print_msg "INFO" "Creating $LOCAL_BINARYS_DIR"
	mkdir $LOCAL_BINARYS_DIR
fi
if [ ! -d $NSO_NED_REPOSITORY ]; then 
	print_msg "INFO" "Creating $NSO_NED_REPOSITORY"
	mkdir $NSO_NED_REPOSITORY
fi
if [ ! -d $NSO_NED_REPOSITORY/$NSO_VERSION ]; then 
	print_msg "INFO" "Creating $NSO_NED_REPOSITORY/$NSO_VERSION"
	mkdir $NSO_NED_REPOSITORY/$NSO_VERSION
fi


if [ "$NSO_INSTALLED" !=  "true" ]; then
	if [ ! -e $LOCAL_BINARYS_DIR/$NSO_BINARY ]; then
		print_msg "INFO" "NSO Binary file does not exist locally, downloading..."
		curl $nso_binary_url  >> $LOCAL_BINARYS_DIR/$NSO_BINARY
		chmod a+x $LOCAL_BINARYS_DIR/$NSO_BINARY
	else
		print_msg "INFO" "NSO Binary file exist"
	fi
	print_msg "INFO" "Performing NSO Local install to $NSO_INSTALL_DIR/$NSO_VERSION"
	$LOCAL_BINARYS_DIR/$NSO_BINARY --local-install $NSO_INSTALL_DIR/$NSO_VERSION
fi

for ned in "${NEDS[@]}"; do
	NED_DOWNLOAD_FILE=""
	print_msg "INFO" "Checking if $ned NED is available on Repo server"
	url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs-pkgs/$ned"
#	echo $url
	if ! curl --output /dev/null --silent --head --fail $url; then
		print_msg "INFO" "** WARNING **: NED $ned at location ($NSO_BINARY_REPO_URL/ncs-pkgs/$ned) does not exist on repo server"
		print_msg "INFO" "Skipping this NED"
	else
		print_msg "INFO" "NED: $ned exists on Repo server"
		NED_DOWNLOAD_VERSION=$NSO_VERSION
		while [[ "$NED_DOWNLOAD_VERSION" == *"."* ]]; do
			print_msg "INFO" "$ned: Retrieving lastest filename for $NED_DOWNLOAD_VERSION"
			file_list_xml=$(curl --silent $url/$NED_DOWNLOAD_VERSION/"$REPO_URL_SORT")
	#		echo $file_list_xml
			while read_dom; do
				if [[ $ENTITY == *"$ned"*"bin"* ]]; then
					NED_DOWNLOAD_FILE=$CONTENT
					print_msg "INFO" "NED - $ned binary: $NED_DOWNLOAD_FILE"
					break
				fi
				if [[ $ENTITY == *"$ned"*"tar.gz"* ]] && [[ $ENTITY != *".sha"* ]]; then
					NED_DOWNLOAD_FILE=$CONTENT
					print_msg "INFO" "NED - $ned file: $NED_DOWNLOAD_FILE"
					break
				fi
			done < <(echo "$file_list_xml")
			NED_FILE_VERSION="${NED_DOWNLOAD_FILE/.tar.gz/}"
			NED_FILE_VERSION="${NED_FILE_VERSION/.signed.bin/}"
			print_msg "INFO" "NED version: $NED_FILE_VERSION"
			if [[ "$NED_FILE_VERSION" == "" ]]; then
				print_msg "INFO" "Ned for $NED_DOWNLOAD_VERSION not available, checking for earlier point release"
			else
				break
			fi
			NED_DOWNLOAD_VERSION=$(echo "$NED_DOWNLOAD_VERSION" | sed 's/\.[^.]*$//')
		done
		if [[ "$NED_FILE_VERSION" == "" ]]; then
			print_msg "INFO" "Ned for $NSO_VERSION not available, skipping download and unpacking"
		else
			print_msg "INFO" "NED base filename: $NED_FILE_VERSION"
			if [ -e $NSO_NED_REPOSITORY/$NSO_VERSION/$NED_FILE_VERSION.tar.gz ]; then
				print_msg "INFO" "NED $ned ($NED_FILE_VERSION) for NSO version $NSO_VERSION already installed in $NSO_NED_REPOSITORY/$NSO_VERSION"
			else
				url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs-pkgs/$ned/$NED_DOWNLOAD_VERSION/$NED_DOWNLOAD_FILE"
				echo $url
				if [[ $NED_DOWNLOAD_FILE == *"$ned"*"tar.gz"* ]]; then
					print_msg "INFO" "Downloading NED $ned for NSO version $NSO_VERSION to $NSO_NED_REPOSITORY/$NSO_VERSION"
					curl $url >> $NSO_NED_REPOSITORY/$NSO_VERSION/$NED_DOWNLOAD_FILE
				else
					if [ -e $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE ]; then
						print_msg "INFO" "NED binary for $ned ($NED_FILE_VERSION) for NSO version $NSO_VERSION already downloaded"
					else
						print_msg "INFO" "NED Binary file ($NED_DOWNLOAD_FILE) does not exist, downloading..."
						curl $url  >> $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE
						chmod a+x $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE
					fi
					if [ -d $NSO_INSTALL_DIR/temp ]; then 
						rm -rf $NSO_INSTALL_DIR/temp
					fi
					print_msg "INFO" "Unpacking NED to $NSO_INSTALL_DIR"/temp
					mkdir $NSO_INSTALL_DIR/temp
					cp $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE $NSO_INSTALL_DIR/temp/$NED_DOWNLOAD_FILE
					( cd $NSO_INSTALL_DIR/temp; eval ./$NED_DOWNLOAD_FILE; echo "Copying NED ($NED_FILE_VERSION.tar.gz) to $NSO_NED_REPOSITORY/$NSO_VERSION"; cp $NSO_INSTALL_DIR/temp/$NED_FILE_VERSION.tar.gz $NSO_NED_REPOSITORY/$NSO_VERSION )
					rm -rf $NSO_INSTALL_DIR/temp
				fi
			fi
		fi
	fi
done

if [ "$DISABLE_ENV_PROXY" == "true" ]; then
	http_proxy=$_http_proxy
	https_proxy=$_https_proxy
	HTTP_PROXY=$_HTTP_PROXY
	HTTPs_PROXY=$_HTTPS_PROXY
fi

echo "Install Complete"

