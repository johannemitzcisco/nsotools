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

.PHONY: simall simclean simbuild simnetworkclean simnetworkbuild simdirs simstart simload simstop

simall: simstop simclean simbuild simload

simclean: stop clean simnetworkclean simdirsclean

simbuild: simnetworkbuild all




# This does the following:
# 1. Deletes the netsim network devices if the netsim directory exists
# 2. Removes any NEDs that are specified in the DEVICES variable
simnetworkclean:
	echo "info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Cleaning Netsim...."; \
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
	echo "info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Setting up simulated network devices..."; \
	networkcreated="false"; \
	for devicetype in $(DEVICES); do \
		echo "devicetype: $$devicetype"; \
		IFS=':'; read -r -a devicearray <<< "$$devicetype"; \
		name="$${devicearray[0]}"; \
		count=$${devicearray[1]}; \
		ned=$${devicearray[2]}; \
		echo "NED: $$name $$ned $$count"; \
		if [ -z $$count ]; then \
			count=-1; \
		fi; \
		echo "NED: $$name $$ned $$count"; \
		nedfileordir=$$(ls -d $(NSO_NEDS)/*-$$ned-*.tar.gz | head -n 1); \
		nedfilename=$$(basename $$nedfileordir); \
		echo "$$ned Ned File $$nedfileordir"; \
		if [[ ! -d $(PROJECT_PACKAGES)/$$nedfilename && ! -h $(PROJECT_PACKAGES)/$$nedfilename && -f $$nedfileordir ]]; then \
			echo "Creating link to NED ($$ned) in $(PROJECT_PACKAGES)"; ln -s $$nedfileordir $(PROJECT_PACKAGES); \
		fi; \
		echo "count $$count"; \
		if [[ $$count > 0 ]]; then \
			echo "Network State: $$networkcreated"; \
			if [ $$networkcreated = "false" ]; then \
				if [ $$count = 1 ]; then echo "Create Device"; $(NETSIM) create-device $$nedfileordir $$name; \
				elif [ $$count > 1 ]; then echo "Create Network"; $(NETSIM) create-network $$nedfileordir $$count $$name; \
				fi; \
				networkcreated="true"; \
			else \
				if [ $$count = 1 ]; then echo "Add Device"; $(NETSIM) add-device $$nedfileordir $$name; \
				elif [ $$count > 1 ]; then echo "Add to Network"; $(NETSIM) add-to-network $$nedfileordir $$count $$name; fi; \
			fi; \
		fi; \
	done
	$(NETSIM) ncs-xml-init > $(INIT_DATA_DIR)/simdevices.xml

#simloaddevices: simdirs
#	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Loading devices)
#	@cp init_data/simulation/cloud-edge0.xml netsim/cloud-edge/cloud-edge0/cdb/
#	@cp init_data/virl-devices.xml ncs-cdb/virl-devices.xml
#	@cp init_data/rootumap.xml ncs-cdb/rootumap.xml
#	@sed 's/$${LOCALUSER}/'$$USER'/g' init_data/rootumap.xml > ncs-cdb/rootumap.xml
#	@cp init_data/virl/virl-authgroup.xml ncs-cdb/virl-authgroup.xml

simstop:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Stopping the Environment)
	$(NETSIM) stop || true
	ncs --stop || true

simload: simstart
	for loadfile in $$(ls $(NSO_POST_START_DATA_DIR)/*.xml  2> /dev/null); do \
		$(NSO_TOOLS_DIR)/loaddata.sh $$loadfile; \
	done

#simstart: simdirsbuild start
simstart:
	$(info >>>>>>>>>>>>>>>>>>>>>>>>>>>  Starting the environment)
	ncs;
	$(NETSIM) start
	for device in $$(ncs-netsim list | grep name | cut -d " " -f1 | cut -d "=" -f2); do \
		echo "device: $$device"; \
		sed -e s/{DEVICE}/$$device/g $(NSO_TOOLS_DIR)/reset-device-config_4.5 | $(NSO_CLI); \
	done; \
	echo "show devices brief" | $(NSO_CLI);

simdirsbuild:
	(for DIR in $(NSO_DIRS); do \
		if [[ ! -d $${DIR} ]]; then mkdir $${DIR}; fi; \
	done)

simdirsclean:
	(for DIR in $(NSO_DIRS); do \
		if [[ -d $${DIR} ]]; then rm -rf $${DIR}; fi; \
	done)
