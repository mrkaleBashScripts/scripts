#!/usr/bin/env bash
#
# NAME:
#   check_mains.sh - Check status of a power supply from electrical mains
#
# SYNOPSIS:
#   check_mains.sh [OPTION [ARG]]
#
# DESCRIPTION:
# Script checks if supplying the local server is from electrical mains or battery
# and sends its status to ThingsBoard IoT platform for processing alarms.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to run under cron.
# - Script sends two-value status to the IoT platform over REST API with curl.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file or credentials file declared in the command line.
# - For security reasons the credentials to IoT platform should be written
#   only in credentials file. Putting them to a command line does not prevent
#   them to be revealed by cron in email messages as a subject.
#
# OPTIONS:
#   -h
#       Help. Show usage description and exit.
#   -s
#       Simmulation. Perform dry run without sending to IoT platform.
#   -V
#       Version. Show version and copyright information and exit.
#   -c
#       Configs. Print listing of all configuration parameters.
#   -o
#       Output. Level of verbose intensity.
#       0=none, 1=errors, 2=mails, 3=info (default), 4=functions, 5=full
#   -m
#       Mailing. Display processing messages suitable for emailing from cron.
#       It is an alias for '-o2'.
#   -v
#       Verbose. Display all processing messages.
#       It is an alias for '-o5'.
#
#   -f  ConfigFile
#       Configuration file for overriding default configuration parameters.
#
#   -p  CredFile
#       Credentials file with access permissions for overriding default
#       configuration parameters.
#
#   -t StatusFile
#       Tick file for writing working status of the script.
#       Should be located in temporary file system.
#
#   -1  Force mains supply
#       Pretend powering from electrical mains.
#
#   -2  Force battery supply
#       Pretend failed electrical mains.
#
# LICENSE:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

# Load library file
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
CONFIG_version="0.2.0"
CONFIG_commands=('grep') # Array of generally needed commands
CONFIG_commands_run=('curl') # List of commands for full running
CONFIG_level_logging=0  # No logging
CONFIG_flag_root=1	# Check root privileges flag
CONFIG_flag_force_mains=0
CONFIG_flag_force_batt=0
CONFIG_mains_active="ON"
CONFIG_mains_idle="OFF"
CONFIG_mains_status=""
CONFIG_mains_dev=""
CONFIG_thingsboard_host=""
CONFIG_thingsboard_token=""
CONFIG_thingsboard_code=0
CONFIG_thingsboard_code_OK=200
CONFIG_status="/tmp/${CONFIG_script}.inf"  # Status file
# <- END _config


# -> BEGIN _environment
grep "WSL" /proc/version >/dev/null
RESULT=$?
if [[ $RESULT -eq 0 ]]
then
	CONFIG_mains_dev="AC1"
else
	CONFIG_mains_dev="ADP1"
fi
# -> END _environment


# -> BEGIN _functions

# @info: Display usage description
# @args: none
# @return: none
# @deps: none
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]]"
	echo "
Check electrical mains power supply status and send it to ThinsBoard IoT platform.
$(process_help -b)
  -1 pretend (force) mains power supply
  -2 pretend (force) battery power supply
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
check_mains () {
	msg="Checking mains power supply status"
	sep=" ... "
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_mains} -eq 1 ]]
	then
		CONFIG_mains_status=${CONFIG_mains_active}
	elif [[ ${CONFIG_flag_force_batt} -eq 1 ]]
	then
		CONFIG_mains_status=${CONFIG_mains_idle}
	else
		# Reading system file
		MAINS_file="/sys/class/power_supply/${CONFIG_mains_dev}/online"
		MAINS_status=$(cat ${MAINS_file})
		if [[ ${MAINS_status} -eq 1 ]]
		then
			CONFIG_mains_status=${CONFIG_mains_active}
		elif [[ ${MAINS_status} -eq 0 ]]
		then
			CONFIG_mains_status=${CONFIG_mains_idle}
		else
			CONFIG_mains_status=""
		fi
	fi
	echo_text -${CONST_level_verbose_info} "${CONFIG_mains_status}."
	if [ -n "${CONFIG_status}" ]
	then
		echo_text -ISL -${CONST_level_verbose_none} "${msg}${sep}${CONFIG_mains_status}." >> "${CONFIG_status}"
	fi
}

# @info:  Send data to ThingsBoard IoT platform
# @args:  none
# @return: global CONFIG_thingsboard_code variable
# @deps:  global CONFIG_mains variables
write_thingsboard () {
	local reqdata
	# Compose data items for a HTTP request payload
	if [[ "${CONFIG_mains_status}" == "${CONFIG_mains_active}" ]]
	then
		reqdata="true"
	elif [[ "${CONFIG_mains_status}" == "${CONFIG_mains_idle}" ]]
	then
		reqdata="false"
	fi
	if [ -n "${reqdata}" ]
	then
		reqdata="\"powerSupply\": ${reqdata}"
	fi
	# Process request payload
	msg="Sending to ThingsBoard"
	sep=" ... "
	if [ -n "${reqdata}" ]
	then
		reqdata="{${reqdata}}" # Create JSON object
	else
		echo_text -${CONST_level_verbose_info} "${msg}${sep}no payload. Exiting."
		fatal_error "${msg} failed with no payload."
fi
	# Compose HTTP request
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(dryrun_token)${sep}${reqdata}"
	if [[ $CONFIG_flag_dryrun -eq 0 && -n "${reqdata}" ]]
	then
		CONFIG_thingsboard_code=$(curl --location --silent \
--write-out %{http_code} \
--output /dev/null \
--connect-timeout 3 \
--request POST "${CONFIG_thingsboard_host}/api/v1/${CONFIG_thingsboard_token}/telemetry" \
--header "Content-Type: application/json" \
--data-raw "${reqdata}")
	else
		CONFIG_thingsboard_code=${CONFIG_thingsboard_code_OK}
	fi
	result="HTTP status code ${CONFIG_thingsboard_code}"
	if [[ ${CONFIG_thingsboard_code} -ne ${CONFIG_thingsboard_code_OK} ]]
	then
		echo_text -${CONST_level_verbose_info} "${sep}failed with ${result}. Exiting."
		fatal_error "${msg} failed with ${result}."
	else
		echo_text -${CONST_level_verbose_info} "${sep}${result}"
	fi
	if [ -n "${CONFIG_status}" ]
	then
		echo_text -ISL -${CONST_level_verbose_none} "${msg}${sep}${result}." >> "${CONFIG_status}"
	fi
}
# <- END _functions


# Process command line parameters
process_options $@
while getopts "${LIB_options}12" opt
do
	case "$opt" in
	1)
		CONFIG_flag_force_mains=1
		CONFIG_flag_force=1
		;;
	2)
		CONFIG_flag_force_batt=1
		CONFIG_flag_force=1
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

init_script
show_configs

process_folder -t "Status" -f "${CONFIG_status}"

# -> Script execution
trap stop_script EXIT

if [ -n "${CONFIG_status}" ]
then
	echo_text -s -${CONST_level_verbose_info} "Writing to status file ... '${CONFIG_status}'."
	echo "" > "${CONFIG_status}"
fi

check_mains
write_thingsboard

# End of script processed by TRAP
