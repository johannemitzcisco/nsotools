# This file can be added to the current NSO project directory to add functionality to the current Makefile that is
# created when one starts a project with the ncs-project command.  This is the project specific settings that will be used
# by the general use setupsimulation.mk.  The purpose is to be able to use the same setupsimulation.mk file while putting
# specific project settings in this file.  To incorporate into the project please refer to the directions in
# setupsimulation.mk.
#

# List of simulated [device name prefixes:number of devices(0 if no netsim devices of this type should be created
# but the NED should be present):device-types (NEDS)] that will be used
# DEVICES = asr-nyc:1:cisco-iosxr asr-lon:1:cisco-iosxr ios:2:cisco-ios pnp-ned:0:cisco-pnp
DEVICES = asr-nyc:1:cisco-iosxr asr-lon:1:cisco-iosxr

# Where the NEDs are located and soft links will be created to
NSO_NEDS = /Applications/Cisco/nso/neds/4.5

# List of directories where xml data files that should be loaded after NSO is started
