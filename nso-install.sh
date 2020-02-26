#!/bin/bash

NSO_BINARY_REPO_URL="https://earth.tail-f.com:8443"
GENERIC_REPO_DOWNLOAD_OPTIONS="--insecure --silent"
BOX_REPO_DOWNLOAD_OPTIONS="--list-only --disable-epsv --ftp-skip-pasv-ip --ftp-ssl"
NSO_REPO_BINARY_DIR="ncs"
NSO_REPO_NED_DIR="ncs-pkgs"
JAVA_RPM_URL='https://download.oracle.com/otn-pub/java/jdk/11.0.1+13/90cf5d8f270a4347a95050320eef3fb7/jdk-11.0.1_linux-x64_bin.rpm'
JAVA_VERSION='jdk-11.0.1'
REPO_URL_SORT='?C=M;O=D' # \ escapes for the script
NSO_LOCAL_NEDS_DIR="neds"
NSO_LOCAL_BINARIES="binaries"
NSO_LOCAL_NSOVERS="nso-versions"
NSO_INSTALL_DIR="(missing)"
REPO_USERNAME="(missing)"
NSO_VERSION="(missing)"
SKIP_OS=false
DISABLE_ENV_PROXY=false
NSO_INSTALLED=false
NEDS=()
DEBUG=false

print_help () {
	echo "
--------  HELP  ----------
Script to download and install the latest NSO version and related NEDs

Support OS versions to install on: MACOS, CentOS

Usage: nso-install -v NSO-VERSION -d NSO-INSTALL-BASE-DIR [OPTIONS]
OPTIONS (The order of the options changes the behavior, best to specify in the order listed here)
[-r NSO-BINARY-REPO-URL] - An http/https url where the software is located
[-u USERNAME] - Username for repo authentication
[-p PASSWORD] - Password for repo authentication
[-i PROXY] - proxy URL
[-x] - disable proxy environment variables 
[-s] - skip install and/or update of required OS packages
[-n NED-NAME]* - Multiple -n entries to specify the NEDs to download and unpack
[-D] - print debug statements
[-h] - print help
[-l] - list the available NEDs on the repository server
[-L SEARCH-STRING ] - list the available NEDs on the repository server that have SEARCH-STRING in their name
[-V] - List available NSO versions

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
	if [[ $1 == "DEBUG" && "$DEBUG" == "true" ]] || [[ $1 != "DEBUG" ]]; then
		printf "$1: %s\n" "$2"
	fi
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

get_username () {
	if [ "$REPO_USERNAME" = "(missing)" ]; then
		print_msg "INFORMATION REQUIRED" "Please enter the NSO binary server host username"
		while IFS= read -r -s -n1 user; do
			if [[ -z $user ]]; then
				echo
				break
			else
				echo -n $user
				REPO_USERNAME+=$user
			fi
		done
	fi
	print_msg "DEBUG" "username set"
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
	print_msg "DEBUG" "password set"
}

request_url () {
#	local url="--silent --insecure --user $REPO_USERNAME:"$REPO_PASSWORD"  $NSO_BINARY_REPO_URL/$1"
#	local url="--verbose --insecure --user $REPO_USERNAME:"$REPO_PASSWORD"  $NSO_BINARY_REPO_URL/$1"
#	local url="--verbose --disable-epsv --ftp-skip-pasv-ip --ftp-ssl --user $REPO_USERNAME:"$REPO_PASSWORD"  $NSO_BINARY_REPO_URL/$1"
	local url="$REPO_DOWNLOAD_OPTIONS --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/$1"
	print_msg "DEBUG" "URL: $url"
	echo `curl $url`
}

finalize () {
	if [ "$DISABLE_ENV_PROXY" == "true" ]; then
		http_proxy=$_http_proxy
		https_proxy=$_https_proxy
		HTTP_PROXY=$_HTTP_PROXY
		HTTPs_PROXY=$_HTTPS_PROXY
	fi
}

get_latest_ned_point_version () {
	get_latest_ned_version $1 $2
	for point_ver in "${sorted[@]}"; do
		print_msg "DEBUG" "$point_ver"
		base_ver=$(echo $point_ver | sed 's/\.*..$//')
		print_msg "DEBUG" "Checking $base_ver against $2"
		if [[ $base_ver == $2 ]]; then
			ned_version=$point_ver
			print_msg "DEBUG" "Setting version to $latest_point_ver"
		fi
	done
}

get_latest_ned_version () {
	initialize
	version_list=$(request_url "$NSO_REPO_NED_DIR/$1/")
	print_msg "DEBUG" "URL: $NSO_REPO_NED_DIR/$1"
	count=0
	declare -a vers
	while read_dom; do
		if [[ $ENTITY == "a href="*'/"' ]] && [ "${CONTENT/\//}" != "Parent Directory" ]; then
			vers[$count]=${CONTENT/\//}
			print_msg "DEBUG" ${vers[$count]}
			count=$(( $count + 1 ))
		fi
	done < <(echo "$version_list")
	IFS=$'\n' sorted=($(sort <<<"${vers[*]}"))
	ned_version=${sorted[${#sorted[@]} - 1]}
	unset IFS
}

list_available_nso_versions () {
	initialize
	local repo_search=""
	if [ "$1" != "" ]; then
#		repo_search="?C=N;O=A;P=*$1*"
		repo_search="?C=N;O=A"
#		repo_search=""
	fi
	local url="$NSO_REPO_BINARY_DIR/$repo_search"
	print_msg "INFO" "Contacting repo server"
	print_msg "DEBUG" "$REPO_DOWNLOAD_OPTIONS --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/$url"
	nso_list_xml=$(request_url "$url")
	count=0
	declare -a vers
	current_version=""
	print_msg "INFO" "Processing version data..."
	while read_dom; do
		if [[ $ENTITY == "a href="* ]]; then
			if [ "${CONTENT/\//}" != "HEAD" ] && [ "${CONTENT/\//}" != "Parent Directory" ] && [[ "${CONTENT/\//}" != *"doc"* ]]; then
				version=${CONTENT/\//}
				prefix="n.*-"
				suffix="\.[a-z]*\..*\..*\..*"
				version=$(expr "$version" : "$prefix\(.*\)$suffix")
				print_msg "DEBUG" $version : ${CONTENT/\//} : $count : ${vers[$count]}
				if [ "$version" != "${vers[$count]}" ]; then
					count=$(( $count + 1 ))
					vers[$count]=$version
				fi
			fi
		fi
	done < <(echo "$nso_list_xml")
	IFS=$'\n' sorted=($(sort <<<"${vers[*]}"))
	echo " -------  Repository NSO Versions List  -----------------"
	printf "%s\n" "${sorted[@]}"
	unset IFS
	print_msg "DEBUG" "$nso_list_xml"
	finalize
	exit 0
}

list_available_repo_neds () {
	initialize
	local repo_search=""
	if [ "$1" != "" ]; then
		repo_search="?C=N;O=A;P=*$1*"
	fi
	local url="$NSO_REPO_NED_DIR/$repo_search"
	ned_list_xml=$(request_url "$url")
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
	finalize
	exit 0
}

initialize () {
	if [ "$INITIALIZED" == "true" ]; then
		return
	fi
	get_username
	get_password

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

	PASSWORD_ECHO="(hidden)"
	if [ -z "$REPO_PASSWORD" ]; then
        	PASSWORD_ECHO="(missing)"
	fi
	REPO_DOWNLOAD_OPTIONS=$GENERIC_REPO_DOWNLOAD_OPTIONS
	if [[ $NSO_BINARY_REPO_URL = *"ftp.box.com"* ]]; then
		REPO_DOWNLOAD_OPTIONS=$BOX_REPO_DOWNLOAD_OPTIONS
		if [[ "$DEBUG" == "true" ]]; then
			REPO_DOWNLOAD_OPTIONS="--verbose $REPO_DOWNLOAD_OPTIONS"
		else 
			REPO_DOWNLOAD_OPTIONS="$REPO_DOWNLOAD_OPTIONS"
		fi
	fi
	print_msg "DEBUG" "Repo Options: $REPO_DOWNLOAD_OPTIONS"
	local url="--user $REPO_USERNAME:"$REPO_PASSWORD" $GENERIC_REPO_DOWNLOAD_OPTIONS -o /dev/null -I -w %{http_code} $NSO_BINARY_REPO_URL"
	local testcreds=`curl $url`
	if [ $testcreds != "200" ]; then
		print_msg "WARNING" "Could not contact repo server ($NSO_BINARY_REPO_URL) with the credentials supplied"
	fi
	INITIALIZED=true
}

while getopts ":d:r:u:p:v:n:L:sxDhlV" opt; do
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
		D) DEBUG=true
		;;
		h) print_help 
		;;
		l) list_available_repo_neds
		;;
		L) list_available_repo_neds "$OPTARG"
		;;
		V) list_available_nso_versions
		;;
		\?) 
			print_error "Invalid option -$OPTARG" "show_help"
		;;
	esac
done

if [ -e $NSO_INSTALL_DIR/$NSO_LOCAL_NSOVERS/$NSO_VERSION/VERSION ]; then
	print_msg "INFO" "NSO version $NSO_VERSION already installed at: $NSO_INSTALL_DIR/$NSO_LOCAL_NSOVERS/$NSO_VERSION/VERSION"
	NSO_INSTALLED=true
elif [ ! -e $LOCAL_BINARYS_DIR/$NSO_BINARY ]; then
	initialize
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
	SKIP_OS="true"
elif [ "$SKIP_OS" == "true" ]; then
	print_msg "WARNING" "You have selected skip OS so this might work, we'll give it a try.  Good Luck!"
else
	print_msg "INFO" "Support for OS update not available for $DISTRO distro, try using the -s option, you never know!"
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

if [[ ("$NSO_INSTALLED" != "true" && ! -e $LOCAL_BINARYS_DIR/$NSO_BINARY ) || "${#NEDS[@]}" > 0 ]]; then
	if [ -z "$REPO_PASSWORD" ] || [ "$REPO_USERNAME" == "(missing)" ]; then
		print_error "Please enter missing information (Username and/or Password)" show_help
	fi
fi
if [ -z "$NSO_VERSION" ] || [ "$NSO_INSTALL_DIR" == "(missing)" ]; then
		print_error "Please enter missing information (Version and/or Install Directory)" show_help
fi
if [ "$DISTRO" == 'unknown' ] && [ "$SKIP_OS" == "true" ]; then
	print_error "$DISTO unsupported by this program.  Only centos and macos supported"
fi

if [ "$SKIP_OS" == "true" ]; then
	print_msg "INFO" "Skipping OS update check"
else
	yum update -y
	yum install -y ant perl wget net-tools zlib-dev openssl-devel sqlite-devel bzip2-devel python-devel
	yum -y groupinstall "Development tools"
	if [ ! -e /usr/java/$JAVA_VERSION/bin/java ]; then
		if [ ! -e $LOCAL_BINARYS_DIR/$JAVA_VERSION-linux-x64.rpm ]; then
			if [ "$DISABLE_ENV_PROXY" == "false" ]; then
				curl -v -j -k -L -H "Cookie: oraclelicense=accept-securebackup-cookie" -x http://proxy.esl.cisco.com:80 $JAVA_RPM_URL >> $LOCAL_BINARYS_DIR/$JAVA_VERSION-linux-x64.rpm
			else
				curl -v -j -k -L -H "Cookie: oraclelicense=accept-securebackup-cookie" $JAVA_RPM_URL >> $LOCAL_BINARYS_DIR/$JAVA_VERSION-linux-x64.rpm
			fi
		fi
		rpm -ihv $LOCAL_BINARYS_DIR/$JAVA_VERSION-linux-x64.rpm
		/usr/sbin/alternatives --install /usr/bin/java java /usr/java/$JAVA_VERSION/bin/java 100
		/usr/sbin/alternatives --set java /usr/java/$JAVA_VERSION/jre/bin/java
	fi
fi

if [ "$NSO_INSTALLED" !=  "true" ]; then
	if [ ! -e $LOCAL_BINARYS_DIR/$NSO_BINARY ]; then
		print_msg "INFO" "NSO Binary file does not exist locally, downloading..."
		if [ ! -d $LOCAL_BINARYS_DIR ]; then 
			print_msg "INFO" "Creating $LOCAL_BINARYS_DIR"
			mkdir -p $LOCAL_BINARYS_DIR
		fi
		nso_binary_url="--insecure --user $REPO_USERNAME:"$REPO_PASSWORD" $NSO_BINARY_REPO_URL/$NSO_REPO_BINARY_DIR/$NSO_BINARY"
		if ! curl --silent --output /dev/null --head --fail $nso_binary_url; then
			print_msg "ERROR" "Version is not valid on repo, File does not exist: $NSO_BINARY_REPO_URL/$NSO_REPO_BINARY_DIR/$NSO_BINARY"
			exit 1
		fi
		curl $nso_binary_url  >> $LOCAL_BINARYS_DIR/$NSO_BINARY
		cmod a+x $LOCAL_BINARYS_DIR/$NSO_BINARY
	else
		print_msg "INFO" "NSO Binary file exist"
	fi
	print_msg "INFO" "Performing NSO Local install to $NSO_INSTALL_DIR/$NSO_LOCAL_NSOVERS/$NSO_VERSION"
	if [ ! -d $NSO_INSTALL_DIR/$NSO_LOCAL_NSOVERS ]; then 
		print_msg "INFO" "Creating $NSO_INSTALL_DIR/$NSO_LOCAL_NSOVERS"
		mkdir -p $NSO_INSTALL_DIR/$NSO_LOCAL_NSOVERS
	fi
	chmod a+x $LOCAL_BINARYS_DIR/$NSO_BINARY
	$LOCAL_BINARYS_DIR/$NSO_BINARY --local-install $NSO_INSTALL_DIR/$NSO_LOCAL_NSOVERS/$NSO_VERSION
fi

if [ ! -d $NSO_NED_REPOSITORY ]; then 
	print_msg "INFO" "Creating $NSO_NED_REPOSITORY"
	mkdir -p $NSO_NED_REPOSITORY
fi
if [ ! -d $NSO_NED_REPOSITORY/$NSO_VERSION ]; then 
	print_msg "INFO" "Creating $NSO_NED_REPOSITORY/$NSO_VERSION"
	mkdir -p $NSO_NED_REPOSITORY/$NSO_VERSION
fi

for ned in "${NEDS[@]}"; do
	initialize
	NED_DOWNLOAD_FILE=""
	print_msg "INFO" "Checking if $ned NED is available on Repo server"
	url="--insecure --user $REPO_USERNAME:$REPO_PASSWORD $NSO_BINARY_REPO_URL/$NSO_REPO_NED_DIR/$ned/"
	print_msg "DEBUG" "$url"
        if ! curl --output /dev/null --silent --head --fail $url; then
		print_msg "WARNING" "NED $ned at location ($NSO_BINARY_REPO_URL/$NSO_REPO_NED_DIR/$ned) does not exist on repo server"
		print_msg "WARNING" "Skipping this NED"
	else
		print_msg "INFO" "NED: $ned exists on Repo server"
		NED_DOWNLOAD_VERSION=$NSO_VERSION
		print_msg "DEBUG" "NED Version: $NED_DOWNLOAD_VERSION"
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
                                #print_msg "INFO" "Could not find version $NED_DOWNLOAD_VERSION, Checking if there is a point release"
				#while [[ $NED_POINT_VERSION != $NED_DOWNLOAD_VERSION ]]; then
				
				print_msg "WARNING" "$ned NED for $NSO_VERSION not available, getting the latest version available"
				get_latest_ned_point_version $ned $NED_DOWNLOAD_VERSION
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
				print_msg "INFO" "NED $ned $NED_FILE_VERSION for NSO version $NSO_VERSION already installed in $NSO_NED_REPOSITORY/$NSO_VERSION"
			else
				url="--insecure --user $REPO_USERNAME:$REPO_PASSWORD $NSO_BINARY_REPO_URL/$NSO_REPO_NED_DIR/$ned/$NED_DOWNLOAD_VERSION/$NED_DOWNLOAD_FILE"
				echo $url
				if [[ $NED_DOWNLOAD_FILE == *"$ned"*"tar.gz"* ]]; then
					print_msg "INFO" "Downloading NED $ned for NSO version $NSO_VERSION to $NSO_NED_REPOSITORY/$NSO_VERSION"
					curl $url >> $NSO_NED_REPOSITORY/$NSO_VERSION/$NED_DOWNLOAD_FILE
				else
					if [ -e $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE ]; then
						print_msg "INFO" "NED binary for $ned $NED_FILE_VERSION for NSO version $NSO_VERSION already downloaded"
					else
						print_msg "INFO" "NED Binary file $NED_DOWNLOAD_FILE does not exist, downloading..."
						curl $url  >> $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE
						chmod a+x $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE
					fi
					if [ -d $NSO_INSTALL_DIR/temp ]; then 
						rm -rf $NSO_INSTALL_DIR/temp
					fi
					print_msg "INFO" "Unpacking NED to $NSO_INSTALL_DIR/temp"
					mkdir -p $NSO_INSTALL_DIR/temp
					cp $LOCAL_BINARYS_DIR/$NED_DOWNLOAD_FILE $NSO_INSTALL_DIR/temp/$NED_DOWNLOAD_FILE
					( cd $NSO_INSTALL_DIR/temp; eval ./$NED_DOWNLOAD_FILE; echo "Copying NED $NED_FILE_VERSION.tar.gz to $NSO_NED_REPOSITORY/$NSO_VERSION"; cp $NSO_INSTALL_DIR/temp/$NED_FILE_VERSION.tar.gz $NSO_NED_REPOSITORY/$NSO_VERSION )
					rm -rf $NSO_INSTALL_DIR/temp
				fi
			fi
		fi
	fi
done

finalize

print_msg "INFO" "Install Complete"

