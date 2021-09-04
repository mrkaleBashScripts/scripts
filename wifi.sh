#!/usr/bin/env bash
#
# NAME:
#   wifi.sh - Manipulate WiFi interface ON and OFF
#
# SYNOPSIS:
#   wifi.sh [OPTION] ARG
#
# DESCRIPTION:
# Script checks if supplying the local server is from electrical mains or battery
# and sends its status to ThingsBoard IoT platform for processing alarms.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to be run manually only.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file or credentials file declared in the command line.
#
# OPTIONS:
#   -h  Help
#       Show usage description and exit.
#
#   -s  Simmulation
#       Perform dry run without sending to IoT platform.
#
#   -V  Version
#       Show version and copyright information and exit.
#
#   -c  Configs
#       Print listing of all configuration parameters.
#
#   -o  Output
#       Level of verbose intensity.
#       0=none, 1=errors, 2=mails, 3=info (default), 4=functions, 5=full
#
#   -m  Mailing
#       Display processing messages suitable for emailing from cron.
#       It is an alias for '-o2'.
#
#   -v  Verbose
#       Display all processing messages.
#       It is an alias for '-o5'.
#
#   -f  ConfigFile
#       Configuration file for overriding default configuration parameters.
#
#   -i  Interface
#       System name of the manipulated wifi interface obtain from 'iwconfig'.
#
# LICENSE:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

# Load library file
LIB_options_exclude=('t' 'l' 'p')
LIB_name="scripts_lib"
for lib in "$LIB_name"{.sh,}
do
	LIB_file="$(command -v "$lib")"
	if [ -z "$LIB_file" ]
	then
		LIB_file="$(dirname $0)/$lib"
	fi
	if [ -f "$LIB_file" ]
	then
		source "$LIB_file"
		unset -v LIB_name LIB_file
		break
	fi
done
if [ "$LIB_name" ]
then
	echo "!!! ERROR -- No file found for library name '$LIB_name'."  1>&2
	exit 1
fi

# -> BEGIN _config
CONFIG_copyright="(c) 2021 Libor Gabaj <libor.gabaj@gmail.com>"
CONFIG_version="0.1.0"
CONFIG_commands=('grep' 'systemctl') # Array of generally needed commands
CONFIG_commands_run=('ifconfig' 'iwconfig') # List of commands for full running
CONFIG_flag_root=1	# Check root privileges flag
CONFIG_ifce_name=""	# Wifi interface system name
CONFIG_ifce_on="UP"	# Wifi interface action for turning it on
CONFIG_ifce_off="DOWN"	# Wifi interface action for turning it off
CONFIG_ifce_action=""	# Wifi interface manipulation action
# <- END _config


# -> BEGIN _functions

# @info: Display usage description
# @args: none
# @return: none
# @deps: none
show_help () {
	echo
	echo "${CONFIG_script} [OPTION] ${CONFIG_ifce_on} | ${CONFIG_ifce_off}"
	echo "
Turn on or off the wifi interface and dhcp service for it.
$(process_help -o)
  -i interface: wifi interface system name to be manipulated (see 'iwconfig')

  ${CONFIG_ifce_on}: action for turning interface on
  ${CONFIG_ifce_off}: action for turning interface off
$(process_help -f)
"
}

# @info: Actions at finishing script invoked by 'trap'
# @args: none
# @return: none
# @deps: Overloaded library function
stop_script () {
	show_manifest STOP
}

# @info:  Checking mains status
# @args:  none
# @return: global config variable
# @deps:  Overloaded library function
wifi_action () {
	msg="Setting wifi interface '${CONFIG_ifce_name}'"
	echo_text -h -${CONST_level_verbose_info} "${msg}$(dryrun_token)${sep}${CONFIG_ifce_action}:"
	# Action
	if [[ ${CONFIG_flag_dryrun} -eq 0 ]]
	then
		if [[ "${CONFIG_ifce_action}" == "${CONFIG_ifce_on}" ]]
		then
			ifconfig ${CONFIG_ifce_name} up
			systemctl enable wpa_supplicant.service
			systemctl start wpa_supplicant.service
			systemctl enable dhclient.service
			systemctl start dhclient.service
			dhclient -v ${CONFIG_ifce_name}
		elif [[ "${CONFIG_ifce_action}" == "${CONFIG_ifce_off}" ]]
		then
			dhclient -r ${CONFIG_ifce_name}
			systemctl stop wpa_supplicant.service
			systemctl disable wpa_supplicant.service
			systemctl stop dhclient.service
			systemctl disable dhclient.service
			ifconfig ${CONFIG_ifce_name} down
		fi
	fi
	# Show result
	systemctl status wpa_supplicant.service | grep ".service\|Active:"
	systemctl status dhclient.service | grep ".service\|Active:"
	iwconfig ${CONFIG_ifce_name}
	ifconfig ${CONFIG_ifce_name}
}

# <- END _functions


# Process command line options
process_options $@
while getopts "${LIB_options}i:" opt
do
	case "$opt" in
	i)
		CONFIG_ifce_name=$OPTARG
		result=$(iwconfig 2>/dev/null |grep "${CONFIG_ifce_name}.*ESSID:")
		if [ $? -ne 0 ]
		then
			fatal_error "Uknown wifi interface '${CONFIG_ifce_name}'!"
		fi
		;;
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)
		case "$OPTARG" in
		*)
			msg="Missing argument for option '-$OPTARG'."
			;;
		esac
		fatal_error "$msg $help"
	esac
done

# Process command line arguments
shift $(($OPTIND-1))
# Action
msghelp=" See help by '${CONFIG_script} -h' please."
if [ -n "$1" ]
then
	CONFIG_ifce_action="$1"
	if [[ "${CONFIG_ifce_action}" != "${CONFIG_ifce_on}" \
	  && "${CONFIG_ifce_action}" != "${CONFIG_ifce_off}" ]]
	then
		fatal_error "Uknown action '${CONFIG_ifce_action}'!${msghelp}"
	fi
else
	fatal_error "No action determined!${msghelp}"
fi

init_script
show_configs

# -> Script execution
trap stop_script EXIT

wifi_action

# End of script processed by TRAP
