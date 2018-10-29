# This file in conjunction conjunction with the simululation.mk file in the project directory can be used  to add 
# functionality to the current Makefile that is created when one starts a project with the ncs-project command.
# To incorporate into the current Makefile please refer to the simulation.mk file for instructions
#
# The intent of the functionality is to allow one to specify the project's simulated devices and their type and then have Make 
# handle linking the NEDs necessary into the project package directory, load the devices with initial config if present in the
# init_data/simulation/devices directory, load any initialization data for the project from the init_data/simulation, and hook
# into the original projects Make system.
#

NSO_CLI=ncs_cli -u admin

.PHONY: simall simstop simclean simbuild simload stop clean simnetworkclean simdirsclean simnetworkbuild simlinklocalpackages simprojectupdate simruninstallers all
simall: simclean simbuild simload

simclean: simstop simnetworkclean simdirsclean

simbuild: simnetworkbuild simlinklocalpackages simprojectupdate simruninstallers all

# This does the following:
# 1. Deletes the netsim network devices if the netsim directory exists
# 2. Removes any NEDs that are specified in the DEVICES variable
simnetworkclean:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Cleaning Netsim  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	if [ -d $(NETSIM_DIR) ]; then $(NETSIM) delete-network; fi; \
	for devicetype in $(DEVICES); do \
		echo "devicetype: $$devicetype"; \
		IFS=':'; read -r -a devicearray <<< "$$devicetype"; \
		ned=$${devicearray[2]}; \
		echo "Looking for $$ned NED to remove"; \
		if [ ! -z $$ned ]; then \
			nedfileordir=$$(ls -d $(PROJECT_PACKAGES)/*-$$ned-* 2> /dev/null | head -n 1); \
			echo "Found: $$nedfileordir"; \
			if [ ! -z $$nedfileordir ]; then \
				echo "Removing $$nedfileordir"; rm -f $$nedfileordir; \
			fi; \
		else \
			echo "No package found for NED, ignoring"; \
		fi; \
		nedfileordir=""; \
	done


# This does the following:
# 1. Creates the netsim network
# 2. Creates a device(s) based on the DEVICES variable
# 3. Creates a symbolic link to the latest version of the ned in the NEDS_DIR variable directory using
# 4. Outputs a load_merge xml file of the devices in the INIT_DATA_DIR variable directory
simnetworkbuild: simdirsbuild
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Setting up simulated network devices <<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	devicecount=0; \
	simdevicecount=0; \
	networkcreated="false"; \
	for devicetype in $(DEVICES); do \
		echo "devicetype: $$devicetype"; \
		IFS=':'; read -r -a devicearray <<< "$$devicetype"; \
		name="$${devicearray[0]}"; \
		count=$${devicearray[1]}; \
		ned=$${devicearray[2]}; \
		type=$${devicearray[3]}; \
		echo "NED: $$name $$ned $$count $$type"; \
		devicecount=$$(($$devicecount + $$count)); \
		if [ "$$type" = "sim" ]; then \
			simdevicecount=$$(($$simdevicecount + $$count)); \
		fi; \
		if [ -z $$count ]; then \
			count=-1; \
		fi; \
		nedfileordir=$$(ls -dt $(NSO_NEDS)/*-$$ned-*.tar.gz | head -n 1); \
		nedfilename=$$(basename $$nedfileordir); \
		echo "$$ned Ned File $$nedfileordir"; \
		if [[ ! -d $(PROJECT_PACKAGES)/$$nedfilename && ! -h $(PROJECT_PACKAGES)/$$nedfilename && -f $$nedfileordir ]]; then \
			echo "Creating link to NED ($$ned) in $(PROJECT_PACKAGES)"; ln -s $$nedfileordir $(PROJECT_PACKAGES); \
		fi; \
		if [[ $$count -gt 0 ]]; then \
			echo "Network State: $$networkcreated"; \
			if [ "$$networkcreated" = "false" ]; then \
				if [ "$$count" -eq 1 ]; then echo "Create Device"; $(NETSIM) create-device $$nedfileordir $$name; \
				elif [ "$$count" -gt 1 ]; then echo "Create Network"; $(NETSIM) create-network $$nedfileordir $$count $$name; \
				fi; \
				networkcreated="true"; \
			else \
				if [ "$$count" -eq 1 ]; then echo "Add Device"; $(NETSIM) add-device $$nedfileordir $$name; \
				elif [ "$$count" -gt 1 ]; then echo "Add to Network"; $(NETSIM) add-to-network $$nedfileordir $$count $$name; fi; \
			fi; \
		fi; \
	done; \
	echo "Total Device Count: $$devicecount"; \
	echo "Simulated Device Count: $$simdevicecount"; \
	if [ "$$devicecount" -gt 0 ]; then \
		echo "here"; \
		$(NETSIM) ncs-xml-init > $(INIT_DATA_DIR)/simdevices.xml; \
	fi

simstop:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Stopping the Environment <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	if [[ -d $(NETSIM_DIR) ]]; then $(NETSIM) stop || true; fi; \
	ncs --stop || true

simload: simstart
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Loading Data <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	for data_load_dir in $(NSO_POST_START_DATA_DIR); do \
		echo "Load Directory: $$data_load_dir"; \
		for loadfile in $$(ls $$data_load_dir/*.xml  2> /dev/null); do \
			echo "Load file: $$loadfile"; \
			$(NSO_TOOLS_DIR)/loaddata.sh $$loadfile; \
		done; \
	done
	echo "request devices fetch-ssh-host-keys" | $(NSO_CLI)
	echo "request devices sync-from" | $(NSO_CLI)

simstart: 
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Starting the environment <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	ncs_running=`ncs --status | grep running: | wc -l | sed -e 's/^[[:space:]]*//'`; \
	if [ "$$ncs_running" -ne 1 ]; then \
		ncs; \
	fi
	simdevicecount=`ls -l netsim | wc -l`; \
	simdevicecount=$$(($$simdevicecount - 1)); \
	if [ "$$simdevicecount" -gt 0 ]; then \
		for device in $$(ncs-netsim list | grep name | cut -d " " -f1 | cut -d "=" -f2); do \
			netsim_running=`ncs-netsim status $$device | grep running: | wc -l | sed -e 's/^[[:space:]]*//'`; \
			if [ "$$netsim_running" -ne 1 ]; then \
				$(NETSIM) start $$device; \
			fi; \
			echo "Resetting device: $$device"; \
			sed -e s/{DEVICE}/$$device/g $(NSO_TOOLS_DIR)/reset-device-config_4.5 | $(NSO_CLI); \
		done; \
	fi
	echo "show devices brief" | $(NSO_CLI);

# Make all NSO_DIRS directories
simdirsbuild:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Creating Directories <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	(for DIR in $(NSO_DIRS); do \
		if [[ ! -d $${DIR} ]]; then mkdir $${DIR}; fi; \
	done)
	if [[ ! -d $(PROJECT_PACKAGES) ]]; then mkdir $(PROJECT_PACKAGES); fi; \

# Delete all NSO_DIRS directories
simdirsclean:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Cleaning Directories  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	(for DIR in $(NSO_DIRS); do \
		if [[ -d $${DIR} ]]; then rm -rf $${DIR}; fi; \
	done)
	if [[ -d $(PROJECT_PACKAGES) ]]; then find $(PROJECT_PACKAGES) -type l -delete; fi; \

# If the project-meta-data.xml file has been updated to reflect local packages that need to be compiled
# this will make sure that the associate setup.mk file is updated before the project is built
simprojectupdate:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Updating Project <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	ncs-project update -y

# Create symbolic links into the PROJECT_PACKAGES directory for packages listed in the LOCAL_PACKAGES
simlinklocalpackages:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Linking Local Packages  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	echo "Packages to link:  $(LOCAL_PACKAGES)"; \
	(for PACKAGE in $(LOCAL_PACKAGES); do \
		echo "Attemping to link package $$PACKAGE"; \
		(for LOCAL_PACKAGE_DIR in $(LOCAL_PACKAGES_DIR); do \
			echo "$$LOCAL_PACKAGE_DIR/$${PACKAGE}"; \
			if [[ -d "$${LOCAL_PACKAGE_DIR}/$${PACKAGE}" ]]; then \
				ln -s "$${LOCAL_PACKAGE_DIR}/$${PACKAGE}" "$(PROJECT_PACKAGES)/"; \
				echo "Package $$PACKAGE linked successfully"; \
				break; \
			fi; \
		done); \
		if [[ ! -d "$(PROJECT_PACKAGES)/$${PACKAGE}" ]]; then \
			echo $${PACKAGE} not found in any of the specified LOCAL_PACKAGES_DIRs; \
			exit 1; \
		fi; \
	done)

# Run a command, if the command is inside a tar.gz file unpack first to templorary directory
simruninstallers:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Running Installers  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<)
	(for installer in $(FUNC_PACK_INSTALL_CMDS); do \
		mkdir /tmp/nsoinstallers; \
		IFS=':'; read -r -a installerarray <<< "$$installer"; \
		installerfile="$${installerarray[0]}"; \
		installercmd=$${installerarray[1]}; \
		echo "Install source: $$installerfile"; \
		echo "Install cmd: $$installercmd"; \
		if [[ -n "$$installerfile" ]]; then \
			echo "Unpacking Installer"; \
			tar -xzf $$installerfile -C /tmp/nsoinstallers; \
			installercmd="/tmp/nsoinstallers/$$installercmd"; \
		fi; \
		eval $$installercmd; \
		rm -rf /tmp/nsoinstallers; \
	done)

