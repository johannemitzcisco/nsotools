#!/bin/bash

NSO_BINARY_REPO_URL="https://earth.tail-f.com:8443"
NSO_REPO_NED_DIR="ncs-pkgs"
JAVA_RPM_URL='http://download.oracle.com/otn-pub/java/jdk/8u144-b01/090f390dda5b47b9b721c7dfaa008135/jdk-8u144-linux-x64.rpm'
JAVA_VERSION='jdk1.8.0_144'
REPO_URL_SORT='?O=D' # \ escapes for the script
NSO_INSTALL_DIR="(missing)"
REPO_USERNAME="(missing)"
NSO_VERSION="(missing)"
SKIP_OS=false
DISABLE_ENV_PROXY=false
NSO_INSTALLED=false
NEDS=()
DEBUG=true

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
[-l] - list the available NEDs on the repository server
[-L SEARCH-STRING ] - list the available NEDs on the repository server that have SEARCH-STRING in their name
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

request_url () {
	get_username
	get_password
	local url="--silent --insecure --user $REPO_USERNAME:"$REPO_PASSWORD"  $NSO_BINARY_REPO_URL/$1"
	if [ "$DEBUG" == "true" ]; then
		print_msg "DEBUG" "URL: $url"
	fi
	echo `curl $url`
}

get_latest_ned_version () {
	version_list=$(request_url "$NSO_REPO_NED_DIR/$1/$REPO_URL_SORT")
	latest_version=1
	while read_dom; do
		if [[ $ENTITY == "a href="*'/"' ]] && [ "${CONTENT/\//}" != "Parent Directory" ]; then
			ned_version=${CONTENT/\//}
			i=$((${#latest_version}-1))
			latest_point="${latest_version:$i:1}"
			ned_point="${ned_version:$i:1}"
			if [ "$ned_point" = "" ]; then
				ned_point=0
			fi
			if [ "$ned_point" -gt "$latest_point" ]; then
				latest_version=$ned_version
			elif [ "$ned_point" -eq "$latest_point" ]; then
				if [ ${#ned_version} -gt ${#latest_version} ]; then
					latest_version=$ned_version
				else
					break
				fi
			else
				break
			fi
		fi
	done < <(echo "$version_list")
	ned_version=$latest_version
}

list_available_repo_neds () {
	local repo_search=""
	if [ "$1" != "" ]; then
		repo_search="?C=N;O=A;P=*$1*"
	fi
	local url="$NSO_REPO_NED_DIR/$repo_search"
	ned_list_xml=$(request_url $url)
	echo " -------  Repository NED List  -----------------"
	while read_dom; do
		if [[ $ENTITY == "a href="*'/"' ]]; then
			if [ "${CONTENT/\//}" != "HEAD" ] && [ "${CONTENT/\//}" != "Parent Directory" ]; then
				local ned_type=${CONTENT/\//}
				get_latest_ned_version $ned_type
				echo $ned_type: $ned_version
			fi
		fi
	done < <(echo "$ned_list_xml")
	exit 0
}

get_username () {
	if [ "$REPO_USERNAME" = "(missing)" ]; then
		print_msg "INFORMATION REQUIRED" "Please enter the NSO binary server host username"
		while IFS= read -r -s -n1 user; do
			if [[ -z $user ]]; then
				echo
				break
			else
				echo -n '*'
				REPO_USERNAME+=$user
			fi
		done
	fi
}

get_password () {
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
}

while getopts ":d:r:u:p:v:n:L:sxhl" opt; do
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
		l) list_available_repo_neds
		;;
		L) list_available_repo_neds "$OPTARG"
		;;
		\?) 
			print_error "Invalid option -$OPTARG" "show_help"
		;;
	esac
done

get_password

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
else
	print_msg "INFO" "Support for OS update not available for $DISTRO"
fi

if [ -e $NSO_INSTALL_DIR/$NSO_VERSION/VERSION ]; then
	print_msg "INFO" "NSO version $NSO_VERSION already installed"
	NSO_INSTALLED=true
else
	print_msg "INFO" "Checking if version ($NSO_BINARY) is available on repo server"
	nso_binary_url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs/$NSO_BINARY"
	if ! curl --silent --output /dev/null --head --fail $nso_binary_url; then
		print_error "Version is not valid on repo, File does not exist: $NSO_BINARY_REPO_URL/ncs/$NSO_BINARY"
	fi
fi

if [ "$NSO_INSTALLED" !=  "true" ]; then
	if [ ! -e $LOCAL_BINARYS_DIR/$NSO_BINARY ]; then
		print_msg "INFO" "NSO Binary file does not exist locally, downloading..."
		if [ ! -d $LOCAL_BINARYS_DIR ]; then 
			print_msg "INFO" "Creating $LOCAL_BINARYS_DIR"
			mkdir $LOCAL_BINARYS_DIR
		fi
		curl $nso_binary_url  >> $LOCAL_BINARYS_DIR/$NSO_BINARY
		chmod a+x $LOCAL_BINARYS_DIR/$NSO_BINARY
	else
		print_msg "INFO" "NSO Binary file exist"
	fi
	print_msg "INFO" "Performing NSO Local install to $NSO_INSTALL_DIR/$NSO_VERSION"
	if [ ! -d $NSO_INSTALL_DIR ]; then 
		print_msg "INFO" "Creating $NSO_INSTALL_DIR"
		mkdir $NSO_INSTALL_DIR
	fi
	$LOCAL_BINARYS_DIR/$NSO_BINARY --local-install $NSO_INSTALL_DIR/$NSO_VERSION
fi

if [ ! -d $NSO_NED_REPOSITORY ]; then 
	print_msg "INFO" "Creating $NSO_NED_REPOSITORY"
	mkdir $NSO_NED_REPOSITORY
fi
if [ ! -d $NSO_NED_REPOSITORY/$NSO_VERSION ]; then 
	print_msg "INFO" "Creating $NSO_NED_REPOSITORY/$NSO_VERSION"
	mkdir $NSO_NED_REPOSITORY/$NSO_VERSION
fi

for ned in "${NEDS[@]}"; do
	NED_DOWNLOAD_FILE=""
	print_msg "INFO" "Checking if $ned NED is available on Repo server"
	url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/ncs-pkgs/$ned"
	if ! curl --output /dev/null --silent --head --fail $url; then
		print_msg "WARNING" "NED $ned at location ($NSO_BINARY_REPO_URL/ncs-pkgs/$ned) does not exist on repo server"
		print_msg "WARNING" "Skipping this NED"
	else
		print_msg "INFO" "NED: $ned exists on Repo server"
		NED_DOWNLOAD_VERSION=$NSO_VERSION
		while [[ "$NED_DOWNLOAD_VERSION" == *"."* ]]; do
			print_msg "INFO" "$ned: Retrieving lastest filename for $NED_DOWNLOAD_VERSION"
			file_list_xml=$(curl --silent $url/$NED_DOWNLOAD_VERSION/"$REPO_URL_SORT")
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
			if [ "$NED_FILE_VERSION" = "" ] && [ "$NED_DOWNLOAD_VERSION" != "$ned_version" ]; then
				print_msg "WARNING" "$ned NED for $NSO_VERSION not available, getting the latest version available"
				get_latest_ned_version $ned
				NED_DOWNLOAD_VERSION=$ned_version
			else
				break
			fi
		done
		if [[ "$NED_FILE_VERSION" == "" ]]; then
			print_msg "ERROR" "$ned NED for $NSO_VERSION not available"

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

print_msg "INFO" "Install Complete"

